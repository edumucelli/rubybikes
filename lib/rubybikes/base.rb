# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'digest/md5'

class BikeShareSystem
    attr_accessor :tag, :meta, :authed
    def initialize(tag, meta)
        @stations   = []
        @tag        = tag
        @meta       = meta
        # basemeta = dict(BikeShareSystem.meta, **self.meta)
        # self.meta = dict(basemeta, **meta)
        # if not self.meta['name'] and self.meta['system']:
        #     self.meta['name'] = self.meta['system']
    end
end

class BikeShareStation
    attr_accessor :name, :latitude, :longitude, :bikes, :free, :timestamp, :extra
    def initialize
        @name       = nil
        @latitude   = nil
        @longitude  = nil
        @bikes      = 0
        @free       = 0
        # Timestamp is UTC
        @timestamp  = Time.now.utc
        @extra      = {}
    end
    def update
        @timestamp = Time.now.utc
    end
    def get_hash
        unless @extra.has_key?('uid')
            Digest::MD5.hexdigest("#{@name},#{@latitude},#{@longitude}")
        else
            Digest::MD5.hexdigest("#{@name},#{@latitude},#{@longitude},#{@extra['uid']}")
        end
    end
end