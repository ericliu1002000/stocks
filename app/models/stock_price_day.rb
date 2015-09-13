class StockPriceDay < ActiveRecord::Base
  YEAR = [2015, 2014, 2013, 2012, 2011, 2010, 2009, 2008, 2007, 2006, 2005]
  JIDU = [4, 3, 2, 1]




  # StockPriceDay.update_price_day
  def self.update_price_day
    ec = Encoding::Converter.new("gb18030", "UTF-8")
    threads = []
    Stock.all.order("id" => :desc).each_with_index do |stock, i|

      # 1.upto(2000000) do
      #   threads.delete_if { |thread| thread.status == false }
      #   if threads.length > 20
      #     # sleep(1)
      #     pp "还有 #{threads.length} 个线程在跑"
      #
      #   else
      #     # break
      #   end
      # end

      # if i%20 == 0
      #   threads.each { |thr| thr.join }
      # end

      #线程开始
      # t = Thread.new do
        begin
          StockPriceDay.transaction do
            StockPriceDay::YEAR.each do |year|
              StockPriceDay::JIDU.each do |jd|
                spd_count = StockPriceDay.where(jidu: jd, year: year, stock_id: stock.id).count
                next if spd_count > 45
                url = "http://money.finance.sina.com.cn/corp/go.php/vMS_MarketHistory/stockid/#{stock.code}.phtml?year=#{year}&jidu=#{jd}"
                pp url
                # url = "http://money.finance.sina.com.cn/corp/go.php/vMS_MarketHistory/stockid/300302.phtml?year=2015&jidu=2"
                response = RestClient.get url
                content = ec.convert response.body
                content = Nokogiri::HTML(content)
                table = content.css("#FundHoldSharesTable")[0]
                next if table.blank?
                days = table.css("tr")
                riqi = nil
                kaipan = nil
                zuigao = nil
                zuidi = nil
                shoupan = nil
                days.each_with_index { |day, i|
                  # pp i
                  next if i == 0
                  next if i == 1
                  day.css('td').each_with_index { |con, i|
                    case i
                      when 0
                        riqi = con.css('a').text.strip
                      when 1
                        kaipan = con.css('div').text.strip
                      when 2
                        zuigao = con.css('div').text.strip
                      when 3
                        shoupan = con.css('div').text.strip
                      when 4
                        zuidi = con.css('div').text.strip
                    end
                  }
                  _date = nil
                  # pp riqi, kaipan, zuigao, shoupan, zuidi
                  begin
                    _date = Date.parse(riqi)
                  rescue Exception => e
                    next
                  end
                  StockPriceDay.create_stock_price_day stock_id: stock.id,
                                                       trading_day: _date,
                                                       top_price: ((zuigao.to_f)*100).to_i,
                                                       low_price: ((zuidi.to_f)*100).to_i,
                                                       start_price: ((kaipan.to_f)*100).to_i,
                                                       end_price: ((shoupan.to_f)*100).to_i,
                                                       code: stock.code,
                      year: year,
                      jidu: jd


                }
              end
            end
          end

        rescue Exception => e
          pp e
        end
        # ActiveRecord::Base.connection.close

      # end
      # t.join
      # threads << t

      #线程结束
    end
    # 1.upto(2000000) do
    #   sleep(5)
    #   pp '休息.......'
    #
    #   threads.delete_if { |thread| thread.status == false }
    #   pp "还有 #{threads.length} 个线程在跑"
    #   break if threads.blank?
    # end
  end

  def self.create_stock_price_day options
    spd = StockPriceDay.where(stock_id: options[:stock_id], trading_day: options[:trading_day]).first
    if spd.blank?
      spd = StockPriceDay.new stock_id: options[:stock_id],
                              trading_day: options[:trading_day]
      spd.save!
    end
    spd.top_price = options[:top_price]
    spd.low_price = options[:low_price]
    spd.start_price = options[:start_price]
    spd.end_price = options[:end_price]
    spd.code = options[:code]
    spd.year = options[:year]
    spd.jidu = options[:jidu]
    spd.save!
    return
  end
end