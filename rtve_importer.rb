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

def fetchFile(a, url, channel)
    # Download files to the folder
    file_name = Pathname.new(url).basename.to_s

    # If it exists, check if it differs otherwise just add it already
    if File.exist?("/content/channels/#{channel}/#{file_name}")
        File.open('/tmp/' + file_name, 'wb'){ |f| f << a.get(url).body.to_s }

        # Check if it's changed or not
        if !FileUtils.compare_file('/tmp/' + file_name, "/content/channels/#{channel}/#{file_name}")
            FileUtils.rm("/content/channels/#{channel}/#{file_name}")
            FileUtils.mv('/tmp/' + file_name, "/content/channels/#{channel}/#{file_name}")
  
            puts "Updated #{file_name}"
        else
            FileUtils.rm('/tmp/' + file_name)
            puts "Not changed #{file_name}"
        end
    else 
        File.open("/content/channels/#{channel}/#{file_name}", 'wb'){ |f| f << a.get(url).body.to_s }
        puts "Downloaded #{file_name}"
    end

end

puts "Fetching login page..."
a.get('http://www.rtve.es/comunicacion/') do |home_page|
  # Safety first - Grab all XML links
  begin
    xml_files = home_page.links_with(:href => /\/sala-de-comunicacion\/media\/Programacion\//)

    puts "Found #{xml_files.count} files"

    xml_files.each do |link|
        if /La 1/ =~ link.to_s
            fetchFile(a, link.href, "la1.rtve.es")
        elsif /Teledeporte/ =~ link.to_s
            fetchFile(a, link.href, "teledeporte.rtve.es")
        end
    end
  rescue Exception => e
    puts "Couldn't find any files. (#{e.message})"
  end
end