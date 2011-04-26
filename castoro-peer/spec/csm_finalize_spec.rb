#
#   Finalizeright 2010 Ricoh Company, Ltd.
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

require 'castoro-peer/configurations'
require 'castoro-peer/manipulator'
require "castoro-peer/csm_client"

describe Castoro::Peer::Csm::Request::Finalize do
  before do
    @conf = mock(Castoro::Peer::Configurations)
    @conf.stub!(:[]).with(:dir_a_user).and_return('root')
    @conf.stub!(:[]).with(:dir_a_group).and_return('castoro')
    @conf.stub!(:[]).with(:dir_a_perm).and_return('0555')
    Castoro::Peer::Csm::Request.class_variable_set :@@configurations, @conf

    @path1 = "/src/path"
    @path2 = "/dst/path"
  end
  
  context 'when initialize' do
    context "with(#{@path1}, 100)" do
      it 'should raise error' do
        pending "this case should be checked and rescued."
        Proc.new{
          @csm_req = Castoro::Peer::Csm::Request::Finalize.new(@path1, 100)
        }.should raise_error(Castoro::Peer::InternalServerError)
      end
    end

    context "with(100, #{@path2})" do
      it 'should raise error' do
        pending "this case should be checked and rescued."
        Proc.new{
          @csm_req = Castoro::Peer::Csm::Request::Finalize.new(100, @path2)
        }.should raise_error(Castoro::Peer::InternalServerError)
      end
    end

    context 'with("")' do
      it 'should raise error' do
        pending "this case should be checked and rescued."
        Proc.new{
          @csm_req = Castoro::Peer::Csm::Request::Finalize.new("")
        }.should raise_error(Castoro::Peer::InternalServerError)
      end
    end

    context "with('', #{@path2})" do
      it 'should raise error' do
        pending "this case should be checked and rescued."
        Proc.new{
          @csm_req = Castoro::Peer::Csm::Request::Finalize.new("", @path2)
        }.should raise_error(Castoro::Peer::InternalServerError)
      end
    end

    context "with(#{@path1}, '')" do
      it 'should raise error' do
        pending "this case should be checked and rescued."
        Proc.new{
          @csm_req = Castoro::Peer::Csm::Request::Finalize.new(@path1, "")
        }.should raise_error(Castoro::Peer::InternalServerError)
      end
    end

    context "with(#{@path1}, #{@path2})" do
      before do
        @csm_req = Castoro::Peer::Csm::Request::Finalize.new(@path1, @path2)
      end

      it 'should be an instance of Castoro::Peer::Csm::Request::Finalize' do
        @csm_req.should be_kind_of Castoro::Peer::Csm::Request::Finalize
      end

      after do
        @csm_req = nil
      end
    end

  end
end

