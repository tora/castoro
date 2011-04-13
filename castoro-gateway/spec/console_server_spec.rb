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

require File.dirname(__FILE__) + '/spec_helper.rb'

describe Castoro::Gateway::ConsoleServer do
  before do
    # the Logger
    @logger = Logger.new(nil)

    @console_port = 30150

    # mock for repository
    @repository = mock Castoro::Gateway::Repository
    @repository.stub!(:new).and_return @repository
    @repository.stub!(:status).and_return "status result"
    @repository.stub!(:peers).and_return "peers result"
    @repository.stub!(:dump).and_return "dump result"
  end

  context "when initialized with the first argument set nil" do
    it "Logger#new(nil) should be called once." do
      Logger.should_receive(:new).with(nil).exactly(1)
      @c = Castoro::Gateway::ConsoleServer.new(nil, @repository, @console_port)
    end

    after do
      @c = nil
    end
  end

  context "when initialized" do
    before do
      @forker = Proc.new { |*args, &block|
        block.call(*args)
      }
      Castoro::Gateway::ConsoleServer.class_variable_set(:@@forker, @forker)
      @c = Castoro::Gateway::ConsoleServer.new(@logger, @repository, @console_port)
    end

    it "@logger should be set an instance of the Logger." do
      logger = @c.instance_variable_get(:@logger)
      logger.should be_kind_of(Logger)
      logger.should == @logger
    end

    it "should be able to start > stop > start ..." do
      100.times {
        @c.start
        @c.stop
      }
    end

    it "#alive? should be false." do
      @c.alive?.should be_false
    end

    it "should be set instance variables correctly from arguments." do
      @c.instance_variable_get(:@logger).should     == @logger
      @c.instance_variable_get(:@repository).should == @repository
      @c.instance_variable_get(:@port).should       == @console_port
    end

    it "#stop should raise server error." do
      Proc.new {
        @c.stop
      }.should raise_error(Castoro::ServerError, "console already stopped.")
    end

    context "when start" do
      it "#alive? should be true." do
        @c.start
        @c.alive?.should be_true
      end

      it "should return self." do
        @c.start.should == @c
      end

      it "#start should raise ServerError." do
        @c.start
        Proc.new {
          @c.start
        }.should raise_error(Castoro::ServerError, "console already started.")
      end

      context "when send status message" do
        it "repository should receive #status with no args exactly 1 tiems." do 
          @c.start
          @repository.should_receive(:status).with(no_args).exactly(1)
          @c.status
        end
      end

      context "when send peers message" do
        it "repository should receive #peers with no args exactly 1 tiems." do 
          @c.start
          @repository.should_receive(:peers).with(no_args).exactly(1)
          @c.peers
        end
      end

      context "when stop" do
        before do
          @c.start
        end
    
        it "#alive? should be false." do
          @c.stop
          @c.alive?.should be_false
        end

        it "should return self." do
          @c.stop.should == @c
        end
      end
    end
  end

  after do
    @repository = nil

    @c.stop if @c.alive? rescue nil
    @c = nil
  end
end
