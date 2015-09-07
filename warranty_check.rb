#!/usr/bin/ruby

# Code examples from https://github.com/kwolf/dell_info/blob/master/lib/facter/dell_info.rb  and
# # https://github.com/camptocamp/puppet-dell/blob/master/lib/facter/util/warranty.rb

require "rubygems"
require "json"
require "net/https"
require "uri"
require "open-uri"
require "date"
require "facter"

if Facter.value('manufacturer').downcase =~ /dell/ && Facter.value('kernel') == 'Linux' && Facter.value('domain') != 'test.exmaple.net'
  $cachefile = '/var/cache/.facter_warranty_info.fact'

  def webquery
    #$cachefile = '/var/cache/.facter_warranty_info.fact'
    uri = URI.parse("https://api.dell.com/support/v2/assetinfo/warranty/tags.json?apikey=1adecee8a60444738f280aad1cd87d0e&svctags=#{Facter.value('serialnumber')}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    $dell_cache = JSON.parse(response.body)

    # Write JSON to cache file
    File.open($cachefile, "w") do |out|
      out.write(JSON.pretty_generate($dell_cache))
    end
    rescue
  end

  # Remove file if it contains the old yaml syntax
  if File.exists?($cachefile) && File.readlines($cachefile).grep(/---/).size > 0
    File.delete($cachefile)
  end

  if File.exists?($cachefile) and !File.zero?($cachefile)
   $dell_cache = JSON.load(File.read($cachefile))
   warranties = $dell_cache['GetAssetWarrantyResponse']['GetAssetWarrantyResult']['Response']['DellAsset']['Warranties']['Warranty']
   warranties.each_with_index do |warranty,index|
     enddate = Date.parse(warranty['EndDate'])
     days_left = enddate - Date.today
     if days_left < 5
       webquery
       break
     end
   end
  elsif !File.exists?($cachefile) or File.zero?($cachefile)
    webquery
  end

  # Get/Set and purchase date
  pd = $dell_cache['GetAssetWarrantyResponse']['GetAssetWarrantyResult']['Response']['DellAsset']['ShipDate']
  purchase_date = Date.parse(pd)
  Facter.add(:purchase_date) do
    setcode do
      purchase_date.strftime("%m-%d-%Y")
    end
  end

  # Determine the server age
  age = (Date.today - purchase_date).to_i
  Facter.add(:server_age_days) do
    setcode do
      age
    end
  end

  # Get/Set the order number
  ordernum = $dell_cache['GetAssetWarrantyResponse']['GetAssetWarrantyResult']['Response']['DellAsset']['OrderNumber']
  Facter.add(:dell_order_number) do
    setcode do
      ordernum.to_s
    end
  end

  # Get/Set Warranty details
  warranties = $dell_cache['GetAssetWarrantyResponse']['GetAssetWarrantyResult']['Response']['DellAsset']['Warranties']['Warranty']

  warranties.each_with_index do |warranty,index|

    Facter.add("warranty#{index}_description") do
      setcode do
        warranty['ServiceLevelDescription'].to_s
      end
    end

    enddate = Date.parse(warranty['EndDate'])
    Facter.add("warranty#{index}_expires") do
      setcode do
        enddate.strftime("%m-%d-%Y")
      end
    end

    days_left = enddate - Date.today
    Facter.add("warranty#{index}_days_left") do
      setcode do
        days_left.to_s
      end
    end

    if days_left.to_i > 0
      warranty_status = "Current"
    else
      warranty_status = "Expired"
    end

    Facter.add("warranty#{index}_status") do
      setcode do
        warranty_status.to_s
      end
    end
  end
end
