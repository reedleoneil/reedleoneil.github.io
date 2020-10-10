require_relative 'client'
require 'os'
require 'json'
require 'sys/proctable'
include Sys

def host()
  { :host => OS.windows? ? `whoami`.strip : `uname -n`.strip + '\\' + `whoami`.strip }
end

def ip()
  #open('http://whatismyip.akamai.com').read
  { :ip => nil }
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

client = Client.new

last_ping_time = Time.now
loop do
	begin
		if client.internals[:mqtt].connected? then
			client.internals[:mqtt].mqtt_loop
			if last_ping_time <= Time.now - 12 then
				client.ping
				last_ping_time = Time.now
        client.publish('reedleoneil/system_info/host', host().to_json)
        client.publish('reedleoneil/system_info/ip', ip().to_json, true, 2)
        client.publish('reedleoneil/system_info/os', os().to_json, true, 2)
        client.publish('reedleoneil/system_info/cpu', cpu().to_json, true, 2)
        client.publish('reedleoneil/system_info/memory', memory().to_json, true, 2)
        client.publish('reedleoneil/system_info/disk', disk().to_json, true, 2)
        client.publish('reedleoneil/system_info/network', network().to_json, true, 2)
        client.publish('reedleoneil/system_info/processes', processes().to_json, true, 2)
			end
		else
			client.connect() if !client.connecting?
		end
	rescue StandardError => error
		puts error.full_message
			client.connect() if !client.connecting?
	end
end
