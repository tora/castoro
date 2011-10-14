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

require "castoro-gateway"

require "monitor"

module Castoro
  class BasketCache
    def initialize logger, config
      @logger             = logger
      @return_peer_number = config["return_peer_number"]
      @filter             = eval(config["filter"].to_s) || Proc.new{ |peers| peers }

      if config["random_cache"]
        @cache_class = RandomCache
        @cache = @cache_class.new config["cache_size"]
      else
        @cache_class = Cache
        page_num = [(config["cache_size"] / @cache_class::PAGE_SIZE).ceil, 1].max
        @cache = @cache_class.new page_num
      end
      @locker  = Monitor.new

      @cache.watchdog_limit = config["watchdog_limit"].to_i
      @weight  = weighting_coefficient @return_peer_number
    end

    def method_missing method_name, *arguments
      self.class.instance_eval {
        define_method(method_name) { |*args|
          @locker.synchronize { @cache.send method_name, *args }
        }
      }
      @locker.synchronize { @cache.send method_name, *arguments }
    end

    def insert basket, host, base_path
      raise "Nil cannot be set to basket." if basket.nil?
      raise "Nil cannot be set to host."   if host.nil?
      basket = basket.to_basket

      @logger.debug {
        "insert into cache data, host => #{host}, key => #{basket.content},#{basket.type},#{basket.revision}, base_path => #{base_path}"
      }
      @locker.synchronize {
        @cache.peers[host].insert(basket.content, basket.type, basket.revision, base_path)
      }
    end

    def erase_by_peer_and_key host, basket
      raise "Nil cannot be set to basket." if basket.nil?
      raise "Nil cannot be set to host."   if host.nil?
      basket = basket.to_basket

      @logger.debug {
        "drop cache data, host => #{host}, key => #{basket.content},#{basket.type},#{basket.revision}"
      }
      @locker.synchronize {
        @cache.peers[host].erase(basket.content, basket.type, basket.revision)
      }
    end

    def find_by_key basket
      raise "Nil cannot be set to basket." if basket.nil?
      basket = basket.to_basket

      @logger.debug { "find cache data by key, #{basket.content},#{basket.type},#{basket.revision}" }

      @locker.synchronize {
        result = {}
        # [ToDo] If #find returned nil, the basket is removed.
        (@cache.find(basket.content, basket.type, basket.revision)||[]).each { |path|
          elements = path.split(":")
          result[elements[0]] = elements[1]
        }
        result
      }
    end

    ##
    # fetch satisfied Peer.
    #
    def find_peers hints = {}
      @locker.synchronize {
        availables = @filter.call(@cache.peers.find(hints["length"].to_i), hints["class"])
        availables.sort_by{ rand }[0..(@return_peer_number-1)]
      }
    end

    ##
    # fetch satisfied Peer
    # and return the array that preferentially sorted by capacity.
    #
    #
    def preferentially_find_peers hints = {}
      @locker.synchronize {
        availables = find_peers hints
        preferentially_sort_by_capacity availables
      }
    end

    ##
    # set status to Cache::Peers
    #
    # === Args
    #
    # +peer_id+::
    #   the peer id, 32bit numerical value that expresses ip-address.
    # +watchdog_code+::
    #   status code for watchdog
    # +available+::
    #   capacity that can be used
    #
    def set_status peer_id, watchdog_code, available

      @locker.synchronize {
        p = @cache.peers[peer_id]
        s = p ? p.status[:status] : nil rescue nil
        if s != watchdog_code
          @logger.info { "watchdog status [#{peer_id}] #{s} => #{watchdog_code}"  }
        end
        @cache.peers[peer_id].status = { :status => watchdog_code, :available => available }
      }
    end

    ##
    # The status of hash representation is returned.
    #
    def status
      @logger.info { "status request accepted." }

      @locker.synchronize {
        {
          :CACHE_EXPIRE            => @cache.stat(::Castoro::Cache::DSTAT_CACHE_EXPIRE),
          :CACHE_REQUESTS          => @cache.stat(::Castoro::Cache::DSTAT_CACHE_REQUESTS),
          :CACHE_HITS              => @cache.stat(::Castoro::Cache::DSTAT_CACHE_HITS),
          :CACHE_COUNT_CLEAR       => @cache.stat(::Castoro::Cache::DSTAT_CACHE_COUNT_CLEAR),
          :CACHE_ALLOCATE_PAGES    => @cache.stat(::Castoro::Cache::DSTAT_ALLOCATE_PAGES),
          :CACHE_FREE_PAGES        => @cache.stat(::Castoro::Cache::DSTAT_FREE_PAGES),
          :CACHE_ACTIVE_PAGES      => @cache.stat(::Castoro::Cache::DSTAT_ACTIVE_PAGES),
          :CACHE_HAVE_STATUS_PEERS => @cache.stat(::Castoro::Cache::DSTAT_HAVE_STATUS_PEERS),
          :CACHE_ACTIVE_PEERS      => @cache.stat(::Castoro::Cache::DSTAT_ACTIVE_PEERS),
          :CACHE_READABLE_PEERS    => @cache.stat(::Castoro::Cache::DSTAT_READABLE_PEERS),
        }
      }
    end


    ##
    # cache records is dumped.
    #
    # === Args
    #
    # +io+::
    #   IO object that receives dump result.
    #
    def dump io
      @logger.info { "dump request accepted." }

      @locker.synchronize {
        @cache.dump io
      }
    end

    private

    ##
    # weighting coefficient for #preferentially_find_peers is returned.
    #
    def weighting_coefficient length
      (0..(length-1)).map { |x| 2**x }
    end

    ##
    # preferentially sort peers by capacity.
    # 
    # === Args
    #
    # +availables+::
    #   Array object that each element contains host and capacity.
    #
    def preferentially_sort_by_capacity availables
      availables.map! { |host|
        stat = @cache.peers[host].status[:available] || {}
        [host, stat.to_i]
      }

      i = -1
      availables.map { |host, capa|
        [host, availables.count { |h,c| capa <= c }]
      }.map { |q|
        i += 1
        [q[0], q[1] * @weight[i]]
      }.sort_by { |x| x[1] }.map { |x| x[0] }
    end

  end

end
