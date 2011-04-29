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

  class Workers < Castoro::Workers

    ALLOW_OPTIONS = [
      :basket_base_dir,
      :my_host,
      :gateway_port,
      :facade_port,
      :multicast_addr,
      :multicast_device_addr,
      :worker_count,
    ].freeze

    # initialize.
    #
    # === Args
    #
    # +logger+::
    #   the logger.
    # +generator+::
    #   the sequense generator.
    # +facade+::
    #   core facade.
    # +options+::
    #   console options.
    #
    def initialize logger, publisher, facade, options = {}
      options.reject { |k,v| !(ALLOW_OPTIONS.include? k.to_sym) }.each { |k, v|
        instance_variable_set "@#{k}", v
      }
      super logger, @worker_count
      @publisher = publisher
      @facade = facade
    end

    private

    def work
      args = [@logger, @gateway_port, @multicast_addr, @multicast_device_addr]
      Castoro::Sender::UDP::Multicast.new(*args) { |s|
        nop = Castoro::Protocol::Response::Nop.new(nil)

        until Thread.current[:dying]
          begin
            if (recv_ret = @facade.recv)
              h, d = recv_ret

              case d
              when Castoro::Protocol::Command::Nop
                s.send h, nop, h.ip, h.port

              when Castoro::Protocol::Command::Get
                basket = d.basket
                dir    = archive_dir basket

                if Dir.exist? dir
                  s.send h, get_response(basket, dir), h.ip, h.port
                  @publisher.insert basket, s
                end

              else
                # do nothing.
              end
            end

          rescue => e
            @logger.error { e.message }
            @logger.debug { e.backtrace.join("\n\t") }
          end
        end
      }
    end

    # return archive directory from basketkey.
    #
    # === Args
    #
    # +basket+
    #   the basket key.
    #
    def archive_dir basket
      n    = basket.content
      a, n = n.divmod 1000000000
      b, n = n.divmod 1000000
      c    = n / 1000

      base_dir = File.join @basket_base_dir, basket.type.to_s
      hash_dir = sprintf("%d/%03d/%03d", a, b, c)
      body_dir = basket.to_s

      File.join base_dir, "/baskets/a/", hash_dir, body_dir
    end

    def get_response basket, archive_dir
      Castoro::Protocol::Response::Get.new nil, basket, @my_host => archive_dir
    end

  end

end

