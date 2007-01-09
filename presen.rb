# presen.rb - presentation class
#
# Copyright (C) 2005 Tanaka Akira  <akr@fsij.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

class Presen
  def initialize(data)
    @data = data
  end
  attr_reader :data

  def current_cache(entry)
    entry['_log'].compact.reverse.inject(nil) {|h0, h1|
      if !h1['content'] || !h1['content'].exist?
        h0
      elsif !h0
        h1
      elsif (h0['checksum'] &&
             h1['checksum'] &&
             h0['checksum'] == h1['checksum']) ||
            (h0['checksum_filtered'] &&
             h1['checksum_filtered'] &&
             h0['checksum_filtered'] == h1['checksum_filtered'])
        h1
      else
        break h0
      end
    }
  end
end
