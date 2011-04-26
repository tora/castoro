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

require "castoro-peer/manipulator"

require "logger"
require "yaml"
require "sync"
require "drb/drb"
require "monitor"

module Castoro::Peer::Manipulator #:nodoc:

  class ManipulatorError < Castoro::CastoroError; end

  ##
  # manipulator main class.
  #
  class Service
    DEFAULT_SETTINGS = {
      "logger" => " Proc.new { |logfile| Logger.new(logfile) } ",
      "user" => "root",
      "loglevel" => Logger::INFO,
      "socket" => "/var/castoro/manipulator.sock",
      "socket_mode" => 0666,
      "base_directory" => "/expdsk",
    }
    SETTING_TEMPLATE = "" <<
      "<% require 'logger' %>\n" <<
      {
        "default" => DEFAULT_SETTINGS.merge(
          "loglevel" => "<%= Logger::INFO %>"
        )
      }.to_yaml

    ##
    # initialize.
    #
    # === Args
    #
    # +config+::
    #   manipulator configurations.
    # +logger+::
    #   the logger.
    #
    def initialize config = {}, logger = nil
      @config = DEFAULT_SETTINGS.merge(config || {})
      @logger = logger || Logger.new(STDOUT)
      @logger.level = @config["loglevel"].to_i

      @locker = Monitor.new
    end

    ##
    # start manipulator daemon.
    #
    def start
      @locker.synchronize {
        raise ManipulatorError, "manipulator already started." if alive?

        @logger.info { "*** castoro-manipulator starting. with config\n" + @config.to_yaml }

        # start executor.
        @executor = Executor.new @logger, @config["base_directory"]

        # start drb service.
        druby_uri = "drbunix:#{@config["socket"]}"
        @drb = DRb::DRbServer.new druby_uri, @executor
        File.chmod @config["socket_mode"], @config["socket"] if @config["socket_mode"]
      }
    end

    ##
    # stop manipulator daemon.
    #
    # === Args
    #
    # +force+::
    #   force shudown.
    #
    def stop force = false
      @locker.synchronize {
        raise ManipulatorError, "manipulator already stopped." unless alive?

        # stop drb service.
        @drb.stop_service
        @drb = nil

        # stop manipulator.
        @executor = nil

        @logger.info { "*** castoro-manipulator stopped." }
      }
    end

    ##
    # return the state of alive or not alive.
    #
    def alive?
      @locker.synchronize {
        !! (@drb and @drb.alive? and @executor)
      }
    end

  end

end

