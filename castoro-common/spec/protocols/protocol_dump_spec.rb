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

require File.dirname(__FILE__) + '/../spec_helper.rb'

describe Castoro::Protocol::Command::Dump do
  context 'when initialize' do
    it "should be able to create an instance of dump command." do
      Castoro::Protocol::Command::Dump.new.should be_kind_of(Castoro::Protocol::Command::Dump)
    end

    context "when initialized" do
      before do
        @command = Castoro::Protocol::Command::Dump.new
      end

      it "should be able to use #to_s." do
        JSON.parse(@command.to_s).should ==
          JSON.parse('["1.1","C","DUMP",{}]' + "\r\n")
      end
    end
  end
end

