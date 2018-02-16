require 'rubygems'
require 'mechanize'
require 'pathname'
require 'fileutils'
require 'nokogiri'
require 'dotenv'

class String
  def squish
    dup.squish!
  end
  def squish!
    gsub!(/\A[[:space:]]+/, '')
    gsub!(/[[:space:]]+\z/, '')
    gsub!(/[[:space:]]+/, ' ')
    self
  end
end


# Load dotenv
Dotenv.load

a = Mechanize.new { |agent|
  # Sky refreshes after login
  agent.follow_meta_refresh = true
}

puts "Fetching login page..."
a.get('http://info.sky.de/inhalt/de/programm_info_presseexport_start.jsp') do |home_page|
  puts "Logging in.."
  my_page = home_page.form_with(:name => 'presscustomer.boundary.loginForm') do |form|
    form['login']  = ENV['LOGIN']
    form['password'] = ENV['PASSWORD']
  end.submit

  # Safety first - Grab all XML links
  begin
    xml_files = my_page.links_with(:href => /_xml\.gz/, :text => 'Download')

    puts "Found #{xml_files.count} XML files"

    xml_files.each do |link|
      # Download files to the folder
      file_name = Pathname.new(link.href).basename.to_s.gsub(/\.gz$/, ".xml").gsub(/(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)_xml/, "").gsub(/(\d\d)(\d\d)_xml/, "").gsub("2017", "2018")

      # If it exists, check if it differs otherwise just add it already
      if File.exist?('/content/skyde/' + file_name)
        File.open('/tmp/' + file_name, 'wb'){ |f| f << Zlib::GzipReader.new(StringIO.new(a.get('http://info.sky.de' + link.href).body.to_s)).read }

        # Check if it's changed or not
        if !FileUtils.compare_file('/tmp/' + file_name, '/content/skyde/' + file_name)
          FileUtils.rm('/content/skyde/' + file_name)
          FileUtils.mv('/tmp/' + file_name, '/content/skyde/' + file_name)

          puts "Updated #{file_name}"
        else
          FileUtils.rm('/tmp/' + file_name)
          puts "Not changed #{file_name}"
        end
      else
        File.open('/content/skyde/' + file_name, 'wb'){ |f| f << Zlib::GzipReader.new(StringIO.new(a.get('http://info.sky.de' + link.href).body.to_s)).read }
        puts "Downloaded #{file_name}"
      end

      #File.open(file_name, 'wb'){ |f| f << Zlib::GzipReader.new(StringIO.new(a.get('http://info.sky.de' + link.href).body.to_s)).read }
    end
  rescue Exception => e
    puts "Couldn't find any xml files. (#{e.message})"
  end

  # Log out (sky only allows 1 logged in user per time. It logs you out after a few mins.)
  begin
    log_out = my_page.link_with(:text => 'Logout').click
    puts "Logged out successfully."
  rescue Exception => e
    puts "Couldn't log out successfully. (#{e.message})"
  end
end

puts "Cleaning up the SKYDE folder.."
Dir.foreach('/content/skyde') do |item|
  next if item == '.' or item == '..'

  cur_week = Time.now.strftime('%W').to_i
  cur_year = Time.now.year.to_i

  if result = item.match(/_(\d\d)_(\d\d\d\d)/)
    week, year = result.captures

    if (week.to_i < (cur_week-1)) or (year.to_i < cur_year-1)
      #FileUtils.rm('/content/skyde/' + item)
      puts "Removed #{item}"
    end
  end
end
