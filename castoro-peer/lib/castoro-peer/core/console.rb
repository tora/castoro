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

require "monitor"
require "drb/drb"

module Castoro::Peer::Core #:nodoc:

  class Console

    ALLOW_OPTIONS = [
      :console_allow_host,
      :console_port,
      :gateway_port,
      :multicast_addr,
      :multicast_device_addr,
    ].freeze

    # initialize.
    #
    # === Args
    #
    # +logger+::
    #   the logger.
    # +publisher+::
    #   core publisher.
    # +facade+::
    #   core facade.
    # +workers+::
    #   core workers.
    # +options+::
    #   console options.
    #
    def initialize logger, publisher, facade, workers, watchdog, options = {}
      @logger    = logger
      @publisher = publisher
      @facade    = facade
      @workers   = workers
      @watchdog  = watchdog
      options.reject { |k,v| !(ALLOW_OPTIONS.include? k.to_sym) }.each { |k, v|
        instance_variable_set "@#{k}", v
      }
      @uri = "druby://#{@console_allow_host}:#{@console_port}"

      @locker = Monitor.new
    end

    # start console.
    #
    def start
      @locker.synchronize {
        raise CastoroError, "console already started." if alive?
        @drb = DRb::DRbServer.new @uri, self
      }
    end

    # stop console.
    #
    def stop
      @locker.synchronize {
        raise CastoroError, "console already stopped." unless alive?
        @drb.stop_service
        @drb = nil
      }
    end

    # return the state of alive or not alive.
    #
    def alive?
      @locker.synchronize {
        !! (@drb and @drb.alive?)
      }
    end

    # getter of watchdog status.
    #
    def watchdog_status
      @watchdog.status
    end

    # setter of watchdog status.
    #
    def watchdog_status= value
      @watchdog.status = value.to_i
      publish_watchdog_packet
    end

    # immediate publish watchdog packet.
    #
    def publish_watchdog_packet
      @watchdog.broadcast     
    end

    # publish insert packet.
    #
    def publish_insert_packet basket
      Castoro::Sender::UDP::Multicast.new(@logger, @gateway_port, @multicast_addr, @multicast_device_addr) { |s|
        @publisher.insert basket, s
      }
    end

    # publish drop packet.
    #
    def publish_drop_packet basket
      Castoro::Sender::UDP::Multicast.new(@logger, @gateway_port, @multicast_addr, @multicast_device_addr) { |s|
        @publisher.drop basket, s
      }
    end

  end

end

