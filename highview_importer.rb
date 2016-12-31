require 'rubygems'
require 'mechanize'
require 'pathname'
require 'fileutils'
require 'nokogiri'
require 'dotenv'

# Load dotenv
Dotenv.load

a = Mechanize.new { |agent|
  # Sky refreshes after login
  agent.follow_meta_refresh = true
  agent.user_agent_alias = (Mechanize::AGENT_ALIASES.keys - ['Mechanize']).sample
}

puts "Fetching file list page..."
a.get('http://www.highview.com/programminfo.html') do |home_page|
  #begin
    # DELUXE
    deluxe_files = home_page.links_with(:href => /\/Programminfos\/DELUXE\//)
    deluxe_files.each do |link|
      file_name = Pathname.new(link.href).basename.to_s

      if File.exist?('/content/channels/deluxemusic.tv/' + file_name)
        puts "Downloading http://www.highview.com#{link.href}.."
        File.open('/tmp/' + file_name, 'wb'){ |f| f << a.get('http://www.highview.com' + link.href).body.to_s }

        # Check if it's changed or not
        if !FileUtils.compare_file('/tmp/' + file_name, '/content/channels/deluxemusic.tv/' + file_name)
          FileUtils.rm('/content/channels/deluxemusic.tv/' + file_name)
          FileUtils.mv('/tmp/' + file_name, '/content/channels/deluxemusic.tv/' + file_name)

          puts "Updated #{file_name}"

          # Channels
          #copy_to_channels('/content/channels/deluxemusic.tv/' + file_name)
        else
          FileUtils.rm('/tmp/' + file_name)
          puts "Not changed #{file_name}"
        end
      else
        puts "Downloading http://www.highview.com#{link.href}.."
        File.open('/content/channels/deluxemusic.tv/' + file_name, 'wb'){ |f| f << a.get('http://www.highview.com' + link.href).body.to_s }
        puts "Downloaded #{file_name}"

        # Channels
        #copy_to_channels('/content/channels/deluxemusic.tv/' + file_name)
      end
    end

    # RCK
    rck_files = home_page.links_with(:href => /\/Programminfos\/RCK\//)
    rck_files.each do |link|
      file_name = Pathname.new(link.href).basename.to_s

      if File.exist?('/content/channels/rck-tv.de/' + file_name)
        puts "Downloading http://www.highview.com#{link.href}.."
        File.open('/tmp/' + file_name, 'wb'){ |f| f << a.get('http://www.highview.com' + link.href).body.to_s }

        # Check if it's changed or not
        if !FileUtils.compare_file('/tmp/' + file_name, '/content/channels/rck-tv.de/' + file_name)
          FileUtils.rm('/content/channels/rck-tv.de/' + file_name)
          FileUtils.mv('/tmp/' + file_name, '/content/channels/rck-tv.de/' + file_name)

          puts "Updated #{file_name}"

          # Channels
          #copy_to_channels('/content/channels/rck-tv.de/' + file_name)
        else
          FileUtils.rm('/tmp/' + file_name)
          puts "Not changed #{file_name}"
        end
      else
        puts "Downloading http://www.highview.com#{link.href}.."
        File.open('/content/channels/rck-tv.de/' + file_name, 'wb'){ |f| f << a.get('http://www.highview.com' + link.href).body.to_s }
        puts "Downloaded #{file_name}"

        # Channels
        #copy_to_channels('/content/channels/rck-tv.de/' + file_name)
      end
    end

  #rescue
  #end
end
