# Copyright (c) 2009-2015 Tim Serong <tserong@suse.com>
# See COPYING for license.

require ::File.expand_path("../config/environment",  __FILE__)
map ENV['RAILS_RELATIVE_URL_ROOT'] || "/" do
  run Rails.application
end
