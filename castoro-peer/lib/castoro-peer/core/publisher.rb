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

  class Publisher

    ALLOW_OPTIONS = [
      :basket_base_dir,
      :multicast_device_addr,
      :my_host,
    ].freeze

    # initialize.
    #
    # === Args
    #
    # +logger+::
    #   the logger.
    # +generator+::
    #   sequense generator.
    # +options+::
    #   facade options.
    #
    def initialize logger, generator, options = {}
      @logger = logger
      options.reject { |k,v| !(ALLOW_OPTIONS.include? k.to_sym) }.each { |k, v|
        instance_variable_set "@#{k}", v
      }
      @generator = generator
    end

    def insert basket, sender
      basket = basket.to_basket
      dir = archive_dir basket

      h = Castoro::Protocol::UDPHeader.new @multicast_device_addr, 0, @generator.next
      d = Castoro::Protocol::Command::Insert.new basket, @my_host, dir

      sender.multicast h, d
    end

    def drop basket, sender
      basket = basket.to_basket
      dir = archive_dir basket

      h = Castoro::Protocol::UDPHeader.new @multicast_device_addr, 0, @generator.next
      d = Castoro::Protocol::Command::Drop.new basket, @my_host, dir

      sender.multicast h, d
    end

    private

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

  end

end

