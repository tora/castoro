#
#   Copyright 2010 Ricoh Company, Ltd.
#
#   This file is part of Castoro.
#
#   Castoro is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Lesser General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   Castoro is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public License
#   along with Castoro.  If not, see <http://www.gnu.org/licenses/>.
#

require "castoro-peer/core"

require "socket"
require "monitor"
require "drb/drb"

module Castoro::Peer::Core #:nodoc:

  class Watchdog < Castoro::Workers

    ALLOW_OPTIONS = [
      :basket_base_dir,
      :my_host,
      :multicast_addr,
      :multicast_device_addr,
      :storage_monitor_interval,
      :watchdog_interval,
      :watchdog_port,
    ].freeze

    # initialize.
    #
    # === Args
    #
    # +logger+::
    #   the logger.
    # +generator+::
    #   the sequense generator.
    # +options+::
    #   watchdog options.
    #
    def initialize logger, generator, options = {}
      @logger = logger
      options.reject { |k,v| !(ALLOW_OPTIONS.include? k.to_sym) }.each { |k, v|
        instance_variable_set "@#{k}", v
      }
      super logger, 1, :name => "watchdog"
      @generator = generator

      @status_locker = Mutex.new
      @status = 20
    end

    def status
      @status_locker.synchronize {
        @status
      }
    end

    def status= value
      @status_locker.synchronize {
        @status = value
      }
    end

    private

    def work
      StorageMonitor.start(@logger, :basket_base_dir => @basket_base_dir,
                                    :storage_monitor_interval => @storage_monitor_interval) { |m|

        args = [@logger, @watchdog_port, @multicast_addr, @multicast_device_addr]
        Castoro::Sender::UDP::Multicast.new(*args) { |s|
          until Thread.current[:dying]
            begin
              sleep @watchdog_interval
  
              header = Castoro::Protocol::UDPHeader.new @multicast_device_addr, 0, @generator.next
              alive  = Castoro::Protocol::Command::Alive.new @my_host, @status, m.space_bytes
              s.multicast header, alive
  
            rescue => e
              @logger.error { e.message }
              @logger.debug { e.backtrace.join("\n\t") }
            end
          end
        }
      }
    end

  end

end

