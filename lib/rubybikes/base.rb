# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'digest/md5'

class BikeShareSystem
    attr_accessor :tag, :meta, :sync, :authed, :unifeed
    def initialize(tag, meta)
        @stations   = []
        @tag        = tag
        @meta       = meta
        @sync       = true
        # basemeta = dict(BikeShareSystem.meta, **self.meta)
        # self.meta = dict(basemeta, **meta)
        # if not self.meta['name'] and self.meta['system']:
        #     self.meta['name'] = self.meta['system']
    end
end

class BikeShareStation
    attr_accessor :name, :latitude, :longitude, :bikes, :free, :timestamp, :extra
    def initialize(timestamp = nil)
        @name       = nil
        @latitude   = nil
        @longitude  = nil
        @bikes      = 0
        @free       = 0
        # Timestamp is UTC
        @timestamp  = timestamp || Time.now.utc
        @extra      = {}
    end
    def update
        @timestamp = Time.now.utc
    end
    def get_hash
        Digest::MD5.hexdigest("#{@name},#{@latitude*1E6},#{@longitude*1E6}")
    end
end