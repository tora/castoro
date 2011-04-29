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

require "logger"
require "yaml"
require "monitor"

module Castoro::Peer::Core #:nodoc:

  class Service

    DEFAULT_SETTINGS = {
      :user                     => "castoro",
      :logger                   => " Proc.new { |logfile| Logger.new(logfile) } ",
      :loglevel                 => Logger::INFO,
      :basket_base_dir          => "/expdsk",
      :console_allow_host       => "0.0.0.0",
      :console_port             => 30101,
      :facade_allow_host        => "0.0.0.0",
      :facade_port              => 30112,
      :gateway_port             => 30109,
      :storage_monitor_interval => 60.0,
      :multicast_addr           => "239.192.1.1",
      :multicast_device_addr    => "127.0.0.1",
      :my_host                  => "localhost",
      :recv_expire              => 0.5,
      :watchdog_interval        => 4.0,
      :watchdog_port            => 30113,
      :worker_count             => 3,
    }.freeze

    SETTING_TEMPLATE = "" <<
      "<% require 'logger' %>\n" <<
      {
        "default" => DEFAULT_SETTINGS.inject({}) { |h,(k,v)|
          h[k.to_s] = v
          h
        }.merge(
          "loglevel" => "<%= Logger::INFO %>",
        )
      }.to_yaml.freeze

    # initialize.
    #
    # === Args
    #
    # +logger+::
    #   the logger.
    # +options+::
    #   options.
    #
    # Valid options for +options+ are:
    #
    #   [:host]     allow hosts.
    #
    def initialize logger, options = {}
      @logger    = logger
      @options   = DEFAULT_SETTINGS.merge(options || {})

      @generator = Generator.new @logger, @options
      @publisher = Publisher.new @logger, @generator, @options

      @facade    = Facade.new @logger, @options
      @workers   = Workers.new  @logger, @publisher, @facade, @options
      @watchdog  = Watchdog.new @logger, @generator, @options
      @console   = Console.new @logger, @publisher, @facade, @workers, @watchdog, @options

      @locker    = Monitor.new
    end

    # start core service.
    #
    def start
      @locker.synchronize {
        raise CastoroError, "castoro-core service already started." if alive?
        @facade.start
        @workers.start
        @watchdog.start
        @console.start
      }
    end

    # stop core service.
    #
    # === Args
    #
    # +force+::
    #   force shutdown.
    #
    def stop force = false
      @locker.synchronize {
        raise CastoroError, "castoro-core service already stopped." unless alive?
        @facade.stop
        @workers.stop
        @watchdog.stop
        @console.stop
      }
    end

    # return the state of alive or not alive.
    #
    def alive?
      @locker.synchronize {
        !! (@facade and @facade.alive? and
            @workers and @workers.alive? and
            @watchdog and @watchdog.alive? and
            @console and @console.alive?)
      }
    end

  end

end

