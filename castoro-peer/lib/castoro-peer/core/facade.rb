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

  class Facade

    ALLOW_OPTIONS = [
      :facade_port,
      :multicast_addr,
      :multicast_device_addr,
      :facade_allow_host,
      :recv_expire,
    ].freeze

    # initialize.
    #
    # === Args
    #
    # +logger+::
    #   the logger.
    # +options+::
    #   facade options.
    #
    def initialize logger, options = {}
      @logger = logger
      options.reject { |k,v| !(ALLOW_OPTIONS.include? k.to_sym) }.each { |k, v|
        instance_variable_set "@#{k}", v
      }

      @mreq = IPAddr.new(@multicast_addr).hton + IPAddr.new(@multicast_device_addr).hton

      @locker      = Monitor.new
      @recv_locker = Monitor.new
    end

    # start facade.
    #
    def start
      @locker.synchronize {
        raise CastoroError, "facade already started." if alive?

        @recv_socket = UDPSocket.new
        @recv_socket.bind(@facade_allow_host, @facade_port)
        @recv_socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, @mreq)
        @recv_socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_LOOP, 0)
      }
    end

    # stop facade.
    #
    def stop
      @locker.synchronize {
        raise CastoroError, "facade already stopped." unless alive?

        @recv_socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_DROP_MEMBERSHIP, @mreq)
        @recv_socket.close
        @recv_socket = nil
      }
    end

    # return the state of alive or not alive.
    #
    def alive?
      @locker.synchronize {
        !! (@recv_socket and !@recv_socket.closed?)
      }
    end

    # get packet from udp-socket.
    #
    # when expired, nil is returned.
    #
    def recv
      received = @recv_locker.synchronize {
        return nil unless alive?
        ret = begin
                IO.select([@recv_socket], nil, nil, @recv_expire)
              rescue Errno::EBADF
                raise if alive?
                nil
              end
        return nil unless ret

        readable = ret[0]
        sock     = readable[0]
        data,    = sock.recvfrom(1024)
        data
      }

      lines = received.split("\r\n")
      h = Castoro::Protocol::UDPHeader.parse(lines[0])
      d = Castoro::Protocol.parse(lines[1])

      [h, d]
    end

  end

end

