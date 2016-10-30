require "io/console"
require "open-uri"
require "bundler/setup"

Bundler.require

$username         = ""
$password         = ""
$approve_topics   = false
$errors           = false
$mobile_errors    = false
$browser          = ""
$two_factor_email = ""
mobile         = false
search_count    = 30
searches_per_credit = 3
mobile_searches_per_credit = 2

if ARGV.count == 1 && File.exists?(ARGV[0])
  config_file = File.open(ARGV[0], "r")
  config_file.each do |line|
    split_line = line.chomp.split('=')
    unless split_line[1].nil?
      case split_line[0]
      when "[browser]"
        $browser = split_line[1].to_sym
      when "[username]"
        $username = split_line[1]
      when "[password]"
        $password = split_line[1]
      when "[approve_topics]"
        $approve_topics = split_line[1]
      when "[2faemail]"
        $two_factor = split_line[1]
      end
    end
  end
  config_file.close
end

def login(browser)
  begin
    login = browser.text_field :type => 'email'#, :name => 'login'
    pass = browser.text_field :type => 'password', :name => 'passwd'
    sign_in_button = browser.input :type => 'submit'

    if $username == ""
      puts "Username: "
      $username = STDIN.gets.chomp
    end
    login.when_present.set $username

    if $password == ""
      puts "Password: "
      $password = STDIN.noecho {|i| i.gets}.chomp
    end
    pass.set $password

    sign_in_button.click
    browser.alert.when_present.ok if browser.alert.exists?

  end #while(login.exists? && pass.exists? && sign_in_button.exists?)
  if(browser.url =~ /https:\/\/account\.live\.com\/ar\/cancel\?ru=https:.*/)
    print "SECURITY CHECK\n"
    browser.radio(id: 'idYesOption').set
    browser.input(type: 'button', id: 'iLandingViewAction').when_present.click
    browser.input(type: 'button', id: 'iOptionViewAction').when_present.click
  end

  if($two_factor != "")
    two_factor_email_input = browser.text_field :type => 'email'
    two_factor_button = browser.button :type => 'submit'

    two_factor_email_input.when_present.set $two_factor
    two_factor_button.click

    puts "Two Factor Authentication Code: "
    tfa_code = STDIN.gets.chomp

    two_factor_code_input = browser.text_field :type => "tel"
    two_factor_code_input.when_present.set tfa_code

    two_factor_submit = browser.button :type => 'submit'
    two_factor_submit.click
  end

  print "Logged in as #{$username}\n"
end

def search(search_count, browser)
  begin
    print "Gathering Searches...\n"
    topics_doc = Nokogiri::HTML(open('http://soovle.com/top'))
    topics     = topics_doc.search('div.letter .correction span').to_a.sample(search_count).collect{|x| x.content}
    topics.shuffle!
    print "Found #{search_count} Search Topics\n"
  rescue OpenURI::HTTPError => e
    raise IOError, "Unable to find search topics"
  end


  if $approve_topics
    topics_approved = false
    while !topics_approved
      print "=============\nSEARCH TOPICS\n=============\n"
      topics.each_with_index do |topic, i|
        print "#{(i+1).to_s.rjust(2)}. #{topic}\n"
      end
      print "=============\n=============\n"
      puts "Do you approve these topics? (y|n):"
      if STDIN.gets.chomp.downcase == "y"
        topics_approved = true
      else
        topics = topics_doc.search('div.letter .correction span').to_a.sample(search_count).collect{|x| x.content}
        topics.shuffle!
      end
    end
  end

  begin
    topics.each_with_index do |topic, i|
      print "#{(i+1).to_s.rjust(2)}. Searching for #{topic}\n"
      browser.alert.when_present.ok if browser.alert.exists?
      browser.text_field(:id=>"sb_form_q").when_present.set(topic)
      browser.form(:id=>"sb_form").when_present.submit
      sleep 5 # Wait 5 seconds
    end
    print "\n==================\nSEARCHES COMPLETED\n==================\n"
  rescue Watir::Exception => e
    print "\n*****\nERROR\n*****\n"
    print "There was an error performing the searches:\n#{e.message}\n"
    raise Watir::Exception::WatirException, "Could not find form"
    $errors = true
  rescue Watir::Exception::TimeoutException => e
    print "\n*****\nERROR\n*****\n"
    print "There was an error performing the searches:\n#{e.message}\n"
    raise Watir::Exception::WatirException, "Timeout Occurred"
  end

end

def todo_list(browser, mobile)
  offer_cards = browser.links(class: 'offer-cta')
  offer_card_titles = offer_cards.collect {|o| o.div(class: 'offer-title-height').text unless o.div(class: 'offer-complete-card-button-background').exists? }

  offer_card_titles.each do |offer_title|
    unless offer_title.nil?
      offer_link = browser.div(:text, offer_title).parent.parent.parent.parent.parent
      offer_value = offer_link.span(class: 'card-button-line-height').text
      print "- #{offer_title} - #{offer_value}\n"
      offer_link.click

      browser.windows.last.use
      browser.windows.last.close if browser.windows.length > 1
      sleep 5
    end
  end
=begin
  offer_cards.each do |offer|
    unless offer.div(class: 'offer-complete-card-button-background').exists?
      begin
        offer_title = offer.div(class: 'offer-title-height').text
        offer_value = offer.span(class: 'card-button-line-height').text
        print "- #{offer_title} - #{offer_value}\n"

        offer.click
        browser.alert.when_present.ok if browser.alert.exists?
      rescue Exception => e
        print "\n*****\nERROR\n*****\n"
        print "Problem clicking #{offer_title}\n"
      end

      browser.windows.last.use
      browser.windows.last.close if browser.windows.length > 1
    end
  end
=end

  sleep 5
  if mobile
    search_link = browser.link(text: "Mobile search")
    search_tile = search_link.parent.parent
    search_value_str = search_tile.div(:text, /.*points per search on mobile.*/).text
    pps = search_value_str.match(/.*(\d+) points per search on mobile.*/)[1].to_i
  else
    search_link = browser.link(text: "PC search")
    search_tile = search_link.parent.parent
    search_value_str = search_tile.div(:text, /.*points per search on PC.*/).text
    pps = search_value_str.match(/.*(\d+) points per search on PC.*/)[1].to_i
  end

  progress = search_tile.div(class: 'text-caption').text.match(/(\d+) of (\d+)/)
  current_credit = progress[1].to_i
  max_credit = progress[2].to_i

  search_link.click

  browser.windows.last.use
  search((max_credit - current_credit) / pps, browser) unless max_credit == current_credit
  browser.windows.last.close if browser.windows.length > 1


end

print "\n=======================\nSTARTING REWARDS MOBILE\n=======================\n"
print "Starting Browser\n"
driver = Webdriver::UserAgent.driver(:browser => $browser, :agent => :android_phone, :orientation => :landscape)
b = Watir::Browser.new driver
b.window.resize_to(800, 1000)
mobile = true
b.goto 'login.live.com'

login(b)

b.goto 'https://account.microsoft.com/rewards'

todo_list(b, mobile)

begin
  print "\n======\nSTATUS\n======\n"
  balance = b.div(class: "info-title").text
  print "#{balance} Credits Available\n"
rescue Exception => e
  print "\n*****\nERROR\n*****\n"
  print "There was an error accessing the balances:\n#{e.message}\n"
  $errors = true
end

print "\n===============\nMOBILE COMPLETE\n===============\n"
b.close

print "\n========================\nSTARTING REWARDS DESKTOP\n========================\n"
print "Starting Browser\n"
b = Watir::Browser.new $browser
mobile = false
b.goto 'login.live.com'

login(b)

b.goto 'https://account.microsoft.com/rewards'

todo_list(b, mobile)

begin
  print "\n======\nSTATUS\n======\n"
  balance = b.div(class: "info-title").text
  print "#{balance} Credits Available\n"
rescue Exception => e
  print "\n*****\nERROR\n*****\n"
  print "There was an error accessing the balances:\n#{e.message}\n"
  $errors = true
end

begin
  goal_elem = b.link(id: 'goal').parent.parent
  goal_title = goal_elem.link(id: 'goal').text
  progress_str = goal_elem.div(:text, /\d+,?\d+ of \d+,?\d+/)
  print "\n#{progress_str}\n"
  progress = progress_str.gsub!(/,/,'').match(/(\d+) of (\d+)/)
  percent_complete = ((progress[1].to_f / progress[2].to_f) * 100).floor
  print "#{percent_complete}% Complete"

rescue Exception => e
  print "\nUnable to find goal\n"
end

print "\n================\nDESKTOP COMPLETE\n================\n"

b.close