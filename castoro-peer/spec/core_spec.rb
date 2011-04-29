#
#   Cloneright 2010 Ricoh Company, Ltd.
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

require File.dirname(__FILE__) + '/spec_helper.rb'

require "castoro-peer/core"

describe Castoro::Peer::Core do
  before(:all) do
    @tmpdir = "/tmp"
    @logger = Logger.new $stdout

    @config = {
      :basket_base_dir => @tmpdir,
      :my_host => "foobar",
      :watchdog_interval => 1.5
    }
    @service = Castoro::Peer::Core::Service.new @logger, @config
    @service.start

    @console = DRbObject.new_with_uri "druby://:30101"
  end

  context "when directory already existed." do
    before do
      @dir = File.join(@tmpdir, "/2/baskets/a/0/000/000/1.2.3")
      FileUtils.mkdir_p(@dir) unless File.exist?(@dir)
    end

    it "a correct response should be able to be acquired." do
      h = Castoro::Protocol::UDPHeader.new "127.0.0.1", 12345, 6789
      d = Castoro::Protocol::Command::Get.new "1.2.3"
      i = "127.0.0.1"
      p = 30112

      results = []
      Castoro::Sender::UDP.new(Logger.new(nil)) { |s|
        r = Castoro::Receiver::UDP.new(Logger.new(nil), 12345) { |header, data, ip, port|
          results = [header, data].map { |x| x.to_s }
        }

        r.start
        sleep 2
        s.send h, d, i, p
        sleep 2
        @service.instance_variable_get(:@console).publish_drop_packet "9.9.9"
        # @console.publish_drop_packet "9.9.9"
        sleep 3
        @console.watchdog_status = 30
        @console.publish_watchdog_packet
        sleep 5
        r.stop
      }

      results.should == [
        Castoro::Protocol::UDPHeader.new("127.0.0.1", 12345, 6789).to_s,
        Castoro::Protocol::Response::Get.new(nil, "1.2.3", "foobar" => "/tmp/2/baskets/a/0/000/000/1.2.3").to_s,
      ]
    end

    after do
      FileUtils.rmdir(@dir) if File.exist?(@dir)
    end
  end

  after(:all) do
    @service.stop
    @service = nil
  end
end

