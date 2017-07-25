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

puts "Fetching login page..."
a.get('http://www.highview.com/presse/login/login/nc.html') do |home_page|
  puts "Logging in.."
  my_page = home_page.form do |form|
    form['user']  = ENV['HV_LOGIN']
    form['pass'] = ENV['HV_PASS']
  end.submit

  # Deluxe music
  deluxe_page = my_page.link_with(:href => '/presse/deluxe-music.html').click
  deluxe_files = deluxe_page.links_with(:href => /\/fileadmin\/Webdata\/Presseseite\/Listings\/DELUXE\//)
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
      else
        FileUtils.rm('/tmp/' + file_name)
        puts "Not changed #{file_name}"
      end
    else
      puts "Downloading http://www.highview.com#{link.href}.."
      File.open('/content/channels/deluxemusic.tv/' + file_name, 'wb'){ |f| f << a.get('http://www.highview.com' + link.href).body.to_s }
      puts "Downloaded #{file_name}"
    end
  end

  # RCK
  rck_page = my_page.link_with(:href => '/presse/rck-tv.html').click
  rck_files = rck_page.links_with(:href => /\/fileadmin\/Webdata\/Presseseite\/Listings\/RCK\//)
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
      else
        FileUtils.rm('/tmp/' + file_name)
        puts "Not changed #{file_name}"
      end
    else
      puts "Downloading http://www.highview.com#{link.href}.."
      File.open('/content/channels/rck-tv.de/' + file_name, 'wb'){ |f| f << a.get('http://www.highview.com' + link.href).body.to_s }
      puts "Downloaded #{file_name}"
    end
  end

  # Planet TV
  planet_page = my_page.link_with(:href => '/presse/planet.html').click
  planet_files = planet_page.links_with(:href => /\/fileadmin\/Webdata\/Presseseite\/Bilder\/Planet\/Listings\//)
  planet_files.each do |link|
    file_name = Pathname.new(link.href).basename.to_s

    if File.exist?('/content/channels/planet-tv.de/' + file_name)
      puts "Downloading http://www.highview.com#{link.href}.."
      File.open('/tmp/' + file_name, 'wb'){ |f| f << a.get('http://www.highview.com' + link.href).body.to_s }

      # Check if it's changed or not
      if !FileUtils.compare_file('/tmp/' + file_name, '/content/channels/planet-tv.de/' + file_name)
        FileUtils.rm('/content/channels/planet-tv.de/' + file_name)
        FileUtils.mv('/tmp/' + file_name, '/content/channels/planet-tv.de/' + file_name)

        puts "Updated #{file_name}"
      else
        FileUtils.rm('/tmp/' + file_name)
        puts "Not changed #{file_name}"
      end
    else
      puts "Downloading http://www.highview.com#{link.href}.."
      File.open('/content/channels/planet-tv.de/' + file_name, 'wb'){ |f| f << a.get('http://www.highview.com' + link.href).body.to_s }
      puts "Downloaded #{file_name}"
    end
  end

end
