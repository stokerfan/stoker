class Stoker < ActiveRecord::Base
  CONNECTION_TYPES = ["http", "socket"]
  
  has_many :sensors
  has_many :blowers
  has_many :events
  has_many :cooks do
    def active
      find(:all, :conditions => ["start_time <= ? AND (end_time >= ? OR end_time IS NULL OR end_time = '')", Time.now, Time.now])
    end
  end
  has_many :adjustments, :through => :cooks
  
  validates_presence_of :host, :port, :name
  validates_uniqueness_of :name
  validates_uniqueness_of :host, :scope => :port
  validates_inclusion_of :connection_type, :in => CONNECTION_TYPES
  
  class << self; attr_accessor :skip_update end

  def self.no_update
    Stoker.skip_update = true
    yield
    Stoker.skip_update = false
  end
  
  def net
    @net ||= Net::Stoker.new(host,
      :connection  => self.connection_type, 
      :port        => self.port,
      :output_port => self.output_port, 
      :telnet_port => self.telnet_port
    )
  end
  
  def sync!
    Stoker.transaction do

      self.blowers.clear
      self.sensors.clear
      
      net_stoker = self.net
      net_stoker.get

      Stoker.no_update do
        net_stoker.blowers.each do |nb|
          if blower = Blower.find_or_create_by_serial_number(nb.serial_number)
            blower.update_attributes!(
              :name   => nb.name,
              :stoker => self
            )
          else
            raise "Failed to find or create blower #{nb.serial_number}"
          end
        end

        net_stoker.sensors.each do |ns|
          if sensor = Sensor.find_or_create_by_serial_number(ns.serial_number)
            sensor.update_attributes!(
              :name   => ns.name,
              :target => ns.target,
              :alarm  => ns.alarm,
              :low    => ns.low,
              :high   => ns.high,
              :stoker => self
            )

            if ns.blower_serial_number.to_s != ""
              sensor.blower = Blower.find_by_serial_number(ns.blower_serial_number)
              sensor.save!
            end
        
            Event.create!(
              :stoker => self,
              :sensor => sensor,
              :alarm  => ns.alarm,
              :temp   => ns.temp
            )
          else
            raise "Failed to find or create sensor #{ns.serial_number}"
          end
        end
      end

    end
  end
  
  def status
    if self.events.find(:first, :conditions => ["created_at >= ?", Time.now - 1.minutes])
      "Recently Updated"
    else
      "More than 1 minute since last update"
    end
  end
  
  def host_url
    "http://#{self.host}:#{self.port}"
  end
end
