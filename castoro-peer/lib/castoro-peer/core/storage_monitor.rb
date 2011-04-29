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

module Castoro::Peer::Core #:nodoc:

  # The free space computational method of storage is defined.
  #
  module StorageMeasurable

    private

    # free space is calculated.
    #
    # === Args
    #
    # +directory+::
    #   disk space base directory.
    #
    def measure_space_bytes directory
      df_ret = `#{measure_command} #{directory} 2>&1`
      if $? == 0
        df_ret = df_ret.split("\n").last
        return $3.to_i if df_ret =~ /^.+(\d+) +(\d+) +(\d+) +(\d+)% +.+$/
      end
      nil
    end

    # Free space display commandline is returned.
    #
    def measure_command
      @measure_command ||= if RUBY_PLATFORM.include?("solaris")
                             "DF_BLOCK_SIZE=1 /usr/gnu/bin/df"
                           else
                             "DF_BLOCK_SIZE=1 /bin/df"
                           end
    end

  end

  # StorageMonitor
  #
  # The capacity of the disk is regularly observed.
  #
  # === Example
  #
  #  # init.
  #  m = Castoro::Peer::StorageMonitor.new "/expdsk"
  #
  #  # start
  #  m.start
  #
  #  10.times {
  #    puts m.space_bytes # => The disk free space is displayed.
  #    sleep 3
  #  }
  #
  #  # stop
  #  m.stop 
  #
  class StorageMonitor

    include StorageMeasurable

    ALLOW_OPTIONS = [
      :basket_base_dir,
      :storage_monitor_interval,
    ].freeze

    def self.start logger, options
      StorageMonitor.new(logger, options).tap { |m|
        m.start
        begin
          yield m
        ensure
          m.stop
        end
      }
    end

    # initialize
    #
    # === Args
    #
    # +logger+::
    #   the logger.
    # +options+::
    #   facade options.
    #
    def initialize logger, options
      @logger = logger
      options.reject { |k,v| !(ALLOW_OPTIONS.include? k.to_sym) }.each { |k, v|
        instance_variable_set "@#{k}", v
      }

      @locker = Monitor.new
    end

    # start monitor service.
    #
    def start
      @locker.synchronize {
        raise 'monitor already started.' if alive?

        # first measure.
        @space_bytes = measure_space_bytes(@basket_base_dir)

        # fork
        @thread = Thread.fork { monitor_loop }
      }
    end

    # stop monitor service.
    #
    def stop
      @locker.synchronize {
        raise 'monitor already stopped.' unless alive?
        
        @thread[:dying] = true
        @thread.wakeup rescue nil
        @thread.join
        @thread = nil         
      }
    end

    # Accessor of storage space (bytes)
    #
    def space_bytes
      @locker.synchronize {
        raise 'monitor does not started.' unless alive?
        @space_bytes
      }
    end

    # Return the state of alive or not alive.
    #
    def alive?
      @locker.synchronize { !! @thread }
    end

    private

    # It keeps executing the calculation of space
    # every @storage_monitor_interval second.
    #
    def monitor_loop
      until Thread.current[:dying]
        space_bytes = (measure_space_bytes(@basket_base_dir) || @space_bytes)
        @locker.synchronize { @space_bytes = space_bytes }
        sleep @storage_monitor_interval
      end
    end

  end

end

