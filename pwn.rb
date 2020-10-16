require 'paho-mqtt'
require 'json'

class Pwn
  attr_reader :internals
  def initialize()
    @internals = {
      :mqtt => PahoMqtt::Client.new
    }
    @cmd_topics = []
    @connect_thread
  end

  def add_topic_callback(topic, &block)
    @cmd_topics.push([topic, 2])
    @internals[:mqtt].add_topic_callback(topic, block)
  end

  def publish(topic, payload="", retain=false, qos=0)
    @internals[:mqtt].publish(topic, payload, retain, qos)
  end

  def connect()
    @connect_thread = Thread.new do
      begin
        init_mqtt()
        @internals[:mqtt].connect()
        @internals[:mqtt].subscribe(@cmd_topics) if @cmd_topics.any?
      rescue StandardError => error
        puts error.full_message
        sleep 11
        connect()
      end
    end
  end

  def connecting?
    @connect_thread != nil && @connect_thread.status ? true : false
  end

  def ping()
    @internals[:mqtt].publish('reedleoneil', nil, false, 2)
  end

  private
  def init_mqtt()
    @internals[:mqtt].on_connack do
      @internals[:mqtt].publish('reedleoneil/status', { :status => 'Online' }.to_json , true, 2)
    end
    @internals[:mqtt].host = 'test.mosquitto.org'
    @internals[:mqtt].port = 1883
    @internals[:mqtt].persistent = true
    @internals[:mqtt].blocking = true
    @internals[:mqtt].will_topic = 'reedleoneil/status'
    @internals[:mqtt].will_payload = { :status => 'Offline' }.to_json
    @internals[:mqtt].will_qos = 2
    @internals[:mqtt].will_retain = true
  end
end
