class Stock < ActiveRecord::Base

  has_many :stock_data_infos

  require 'rest-client'
  require 'pp'
  require 'open-uri'
  require 'nokogiri'
  require 'open-uri'


  # 获得指定年份所有A股的负债、利润、现金数据
  def self.get_all_a_stock_info_from_sina year, skip_has_downloaded=false
    Stock.where(stock_type: 1).each do |stock|
      self.transaction do
        next if skip_has_downloaded && stock.download_times>=1
        StockSummary.all.each do |stock_summary|
          get_a_stock_info_from_sina stock.id, stock_summary.id, year
        end
        stock.download_times += 1
        stock.save!
      end
    end
  end


  # 第一次初始获得所有A股数据
  def self.init_get_all_a_stock_info_from_sina skip_has_downloaded=false
    Stock.where(stock_type: 1).each do |stock|

        next if skip_has_downloaded && stock.download_times>=1
        StockSummary.all.each do |stock_summary|
          2016.downto 2004 do |year|
              get_a_stock_info_from_sina stock.id, stock_summary.id, year
          end
        end
        stock.download_times += 1
        stock.save!
    end
  end

  def self.init_get_all_a_stock_info_from_sina_between start_id, end_id, skip_has_downloaded=false
    Stock.where("id >= ? and id <= ?", start_id, end_id).each do |stock|

      next if skip_has_downloaded && stock.download_times>=1
      StockSummary.all.each do |stock_summary|
        2016.downto 2004 do |year|
          get_a_stock_info_from_sina stock.id, stock_summary.id, year
        end
      end
      stock.download_times += 1
      stock.save!
    end
  end


  # 从新浪获得某只A股、相应年份、相应财务数据
  def self.get_a_stock_info_from_sina stock_id, stock_summary_id, year
    self.transaction do

      stock = Stock.find(stock_id)
      stock_summary = StockSummary.find(stock_summary_id)
      pp "###"*50
      pp "stock_id:#{stock.id} name:#{stock.name} stock_summary_id:#{stock_summary.name}   year:#{year}"

      # t_stock_data_info = StockDataInfo.where(stock_id: stock_id, stock_data_item_id: stock_summary.stock_data_items.first.id).where("quarterly_date in (?) ", ["#{year}-03-31", "#{year}-06-30", "#{year}-09-30", "#{year}-12-31"])

      t_stock_data_info = StockDataInfo.where(stock_id: stock_id, stock_data_item_id: stock_summary.stock_data_items.first.id).where("quarterly_date in (?) ", ["#{year}-03-31", "#{year}-06-30", "#{year}-09-30", "#{year}-12-31"])

      unless t_stock_data_info.blank? # 如果此股、此类型、此年份数据已经抓过，就跳过
        pp '存在，跳过'
        return
      end


      uri = case stock_summary.name
              when '资产负债表'
                "http://money.finance.sina.com.cn/corp/go.php/vFD_BalanceSheet/stockid/#{stock.code}/ctrl/#{year}/displaytype/4.phtml"
              when '利润表'
                "http://money.finance.sina.com.cn/corp/go.php/vFD_ProfitStatement/stockid/#{stock.code}/ctrl/#{year}/displaytype/4.phtml"
              when '现金流量表'
                "http://money.finance.sina.com.cn/corp/go.php/vFD_CashFlow/stockid/#{stock.code}/ctrl/#{year}/displaytype/4.phtml"
            end
      pp "#访问url:  #{uri}"
      # doc = Nokogiri::HTML(open(uri).read.force_encoding('GBK').encode("utf-8"))
      response = RestClient.get uri
      ec = Encoding::Converter.new("GBK", "UTF-8")
      doc = ec.convert response.body
      doc = Nokogiri::HTML(doc)
      table_content = doc.xpath("//table").select{|x|x.to_s.include?("BalanceSheetNewTable0")||x.to_s.include?("ProfitStatementNewTable0")}[0] # table内容
      return if table_content.blank?
      # pp "#table_content size: #{table_content.to_s.size}"
      table_content_doc = Nokogiri::HTML(table_content.to_s)
      table_arr = []
      table_content_doc.xpath("//tr").each_with_index do |tr, index|
        next if index == 0
        tr_doc = Nokogiri::HTML(tr.to_s)
        row_arr = []
        tr_doc.xpath("//td").each do |td|
          td_slop = Nokogiri::Slop td.to_s.encode("utf-8")
          row_arr << td_slop.td.content
        end
        table_arr << row_arr
      end
      table_arr.select!{|x|!x.blank?}
      category = ''
      table_arr.each_with_index do |row, index|
        next if index == 0
        row[0] = "其他_#{index}" if row[0].blank? # 空白处理
        if row[1].blank? && row[2].blank? # 暂存目录
          category = row[0]
          next
        elsif row[0].include?('一、') || row[0].include?('二、') || row[0].include?('三、') || row[0].include?('四、') || row[0].include?('五、') || row[0].include?('六、') || row[0].include?('七、') || row[0].include?('八、') || row[0].include?('九、') || row[0].include?('十、')
          category = row[0]
        end
        stock_data_item = StockDataItem.find_or_create_by stock_summary_id: stock_summary.id,
                                                          name: row[0],
                                                          category: category # 获得数据项名称
        end_col_index = row.size - 1
        1.upto end_col_index do |col_index|
          unit = '万元'
          quarterly_date = table_arr[0][col_index]

          stock_data_info = StockDataInfo.where(stock_id: stock.id, stock_data_item_id: stock_data_item.id, quarterly_date: quarterly_date)

          return unless stock_data_info.blank? # 如果此股、此类型、此年份数据已经抓过，就跳过

          StockDataInfo.create! stock_id: stock.id,
                                stock_data_item_id: stock_data_item.id,
                                quarterly_date: quarterly_date,
                                stock_code: stock.code,
                                value: row[col_index].gsub(',',''),
                                monetary_unit: unit,
                                source: '新浪财经',
                                url: uri if stock_data_info.blank? # 指定股票，指定季度，指定数据项  数据不存在，则写数据到数据库
        end
      end
    end
  end

  # 从新浪获得所有港股的财务信息
  def self.get_all_hk_stock_info_from_sina skip_has_downloaded=false
    Stock.where(stock_type: 2).each do |stock|
      self.transaction do
        next if skip_has_downloaded && stock.download_times>=1
        StockSummary.all.each do |stock_summary|
          self.get_hk_stock_info_from_sina stock.id, stock_summary.id
        end
        stock.download_times += 1
        stock.save!
      end
    end
  end


  # 从新浪获得某只港股的财务信息
  def self.get_hk_stock_info_from_sina stock_id, stock_summary_id
    params_get = ['zero', '1', '2', '3']
    stock_summary = StockSummary.find(stock_summary_id)
    body_flag = case stock_summary.name
                  when '资产负债表'
                    'tableGetBalanceSheet'
                  when '利润表'
                    'tableGetFinanceStatus'
                  when '现金流量表'
                    'tableGetCashFlow'
                end
    return if body_flag.blank?
    url_pa = case stock_summary.name
                  when '资产负债表'
                    'getBalanceSheetForjs'
                  when '利润表'
                    'getFinanceStatusForjs'
                  when '现金流量表'
                    'getCashFlowForjs'
             end
    return if url_pa.blank?
    url_pa2 = case stock_summary.name
               when '资产负债表'
                 'balanceSheet'
               when '利润表'
                 'financeStatus'
               when '现金流量表'
                 'cashFlow'
             end
    return if url_pa2.blank?

    stock = Stock.find(stock_id)

    uri = "http://stock.finance.sina.com.cn/hkstock/finance/#{stock.code}.html"
    doc = Nokogiri::HTML(open(uri).read.force_encoding('GBK').encode("utf-8"))

    total_data = []
    sub_item_name_arr = []
    body_content = doc.xpath("//tbody").select{|x|x.to_s.include?(body_flag)}[0] # 负债
    trs_content_doc = Nokogiri::HTML(body_content.to_s)
    trs_content_doc.xpath("//tr").each do |tr| # 获取数据抬头
      td_doc = Nokogiri::HTML tr.to_s
      td_slop = Nokogiri::Slop td_doc.xpath("//th")[0].to_s.encode("utf-8")
      sub_item_name_arr << td_slop.th.content
    end
    total_data << sub_item_name_arr
    pp sub_item_name_arr
    pp "抬头数目：#{sub_item_name_arr.size}"
    params_get.each do |pa| # 获取负债数据
      pp "获取负债数据"
      pp uri
      pp "http://stock.finance.sina.com.cn/hkstock/api/jsonp.php/var%20tableData%20=%20/FinanceStatusService.#{url_pa}?symbol=#{stock.code}&#{url_pa2}=#{pa}"
      response = RestClient.get "http://stock.finance.sina.com.cn/hkstock/api/jsonp.php/var%20tableData%20=%20/FinanceStatusService.#{url_pa}?symbol=#{stock.code}&#{url_pa2}=#{pa}"
      pp "#"*200
      pp response
      if ! response.valid_encoding?
        response = response.encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8')
      end
      response = response.force_encoding("utf-8").gsub(" ","").gsub("vartableData=(","").gsub(");","")
      return if response.blank? || response == 'null'
      response = response.gsub("null","\"--\"")
      pp "response: "
      pp response
      response = JSON.parse response
      response.each do |x|
        total_data << x
      end
    end
    total_data = total_data.transpose
    category = ''
    total_data.each_with_index do |row, index|
      next if row[0] == '报告期' || row[0] == "币种" || row[0] == '报表类型'
      row[0] = "其他_#{index}" if row[0].blank? # 空白处理
      if row[1].blank? && row[2].blank? # 暂存目录
        category = row[0]
        next
      elsif row[0].include?('一、') || row[0].include?('二、') || row[0].include?('三、') || row[0].include?('四、') || row[0].include?('五、') || row[0].include?('六、') || row[0].include?('七、') || row[0].include?('八、') || row[0].include?('九、') || row[0].include?('十、')
        category = row[0]
      end
      stock_data_item = StockDataItem.find_or_create_by stock_summary_id: stock_summary_id,
                                                        name: row[0],
                                                        category: category # 获得数据项名称
      end_col_index = row.size - 1
      1.upto end_col_index do |col_index|
        unit = '百万元'
        quarterly_date = total_data[0][col_index]

        stock_data_info = StockDataInfo.where(stock_id: stock.id, stock_data_item_id: stock_data_item.id, quarterly_date: quarterly_date)
        StockDataInfo.create! stock_id: stock.id,
                              stock_data_item_id: stock_data_item.id,
                              quarterly_date: quarterly_date,
                              stock_code: stock.code,
                              value: row[col_index].gsub(',',''),
                              monetary_unit: unit,
                              source: '新浪财经',
                              url: uri if stock_data_info.blank? # 指定股票，指定季度，指定数据项  数据不存在，则写数据到数据库
      end

    end
  end

  # 从雅虎获得所有美股的财务信息
  def self.get_all_usa_stock_info_from_yahoo skip_has_downloaded=false
    Stock.where(stock_type: 3).each do |stock|
      self.transaction do
        next if skip_has_downloaded && stock.download_times>=1
        StockSummary.all.each do |stock_summary|
          self.get_usa_stock_info_from_yahoo stock.id, stock_summary.id
        end
        stock.download_times += 1
        stock.save!
      end
    end
  end

  # 从雅虎获得某只美的财务信息
  def self.get_usa_stock_info_from_yahoo stock_id, stock_summary_id
      stock = Stock.find(stock_id)

      total_data = []

      stock_summary = StockSummary.find(stock_summary_id)
      uri = case stock_summary.name
                    when '资产负债表'
                      "https://finance.yahoo.com/q/bs?s=#{stock.code}&annual"
                    when '利润表'
                      "https://finance.yahoo.com/q/is?s=#{stock.code}&annual"
                    when '现金流量表'
                      "https://finance.yahoo.com/q/cf?s=#{stock.code}&annual"
                  end
      doc = Nokogiri::HTML(open(uri).read.encode("utf-8"))
      ele_table = doc.xpath("//table").select{|x|x.to_s.include? 'Period Ending'}
      doc_table = Nokogiri::HTML(ele_table.last.to_s)
      return if doc_table.content.blank?
      ele_trs = doc_table.xpath("//tr")
      ele_trs.each_with_index do |ele_tr, index|
        arr = Nokogiri::Slop(ele_tr.to_s).tr.content.split("\n").select{|x|!x.blank?}.collect{|x|x.strip}
        next if arr.blank?
        if arr[0] == "Period Ending"
          tmp_arr = []
          tmp_arr << "Period Ending"
          arr.each do |d|
            next if d == "Period Ending"
            tmp_arr << d.to_date.strftime("%Y-%m-%d")
          end
          arr = tmp_arr
        end

        total_data << arr
      end

      total_data.each_with_index do |row, index|
        next if row[0] == 'Period Ending'
        row[0] = "其他_#{index}" if row[0].blank? # 空白处理
        if row[1].blank? && row[2].blank? # 暂存目录
          category = row[0]
          next
        end
        stock_data_item = StockDataItem.find_or_create_by stock_summary_id: stock_summary_id,
                                                          name: row[0],
                                                          category: category # 获得数据项名称
        end_col_index = row.size - 1
        1.upto end_col_index do |col_index|
          unit = '千美元'
          quarterly_date = total_data[0][col_index]

          stock_data_info = StockDataInfo.where(stock_id: stock.id, stock_data_item_id: stock_data_item.id, quarterly_date: quarterly_date)
          val = row[col_index].gsub(',','').gsub("  ","")
          val = "-#{val.gsub("(","").gsub(")","").gsub(" ","")}" if val.include?("(") && val.include?(")")
          StockDataInfo.create! stock_id: stock.id,
                                stock_data_item_id: stock_data_item.id,
                                quarterly_date: quarterly_date,
                                stock_code: stock.code,
                                value: val.to_f,
                                monetary_unit: unit,
                                source: '雅虎财经',
                                url: uri if stock_data_info.blank? # 指定股票，指定季度，指定数据项  数据不存在，则写数据到数据库
        end

      end
  end


  # 从新浪获得某只港股的财务信息
  # def self.get_hk_stock_info_from_sinabak stock_id
  #   self.transaction do
  #     params_get = ['zero', '1', '2', '3']
  #
  #     stock = Stock.find(stock_id)
  #     uri = "http://stock.finance.sina.com.cn/hkstock/finance/#{stock.code}.html"
  #     doc = Nokogiri::HTML(open(uri).read.force_encoding('GBK').encode("utf-8"))
  #
  #     # 负债数据
  #     stock_summary_id = StockSummary.find_or_create_by(name: '资产负债表').id
  #     fuzhai_data = []
  #     fuzhai_item_name_arr = []
  #     fuzhai_body_content = doc.xpath("//tbody").select{|x|x.to_s.include?("tableGetBalanceSheet")}[0] # 负债
  #     trs_content_doc = Nokogiri::HTML(fuzhai_body_content.to_s)
  #     trs_content_doc.xpath("//tr").each do |tr| # 获取数据抬头
  #       td_doc = Nokogiri::HTML tr.to_s
  #       td_slop = Nokogiri::Slop td_doc.xpath("//th")[0].to_s.encode("utf-8")
  #       fuzhai_item_name_arr << td_slop.th.content
  #     end
  #     fuzhai_data << fuzhai_item_name_arr
  #     pp fuzhai_item_name_arr
  #     pp "抬头数目：#{fuzhai_item_name_arr.size}"
  #     params_get.each do |pa| # 获取负债数据
  #       pp "http://stock.finance.sina.com.cn/hkstock/api/jsonp.php/var%20tableData%20=%20/FinanceStatusService.getBalanceSheetForjs?symbol=#{stock.code}&balanceSheet=#{pa}"
  #       response = RestClient.get "http://stock.finance.sina.com.cn/hkstock/api/jsonp.php/var%20tableData%20=%20/FinanceStatusService.getBalanceSheetForjs?symbol=#{stock.code}&balanceSheet=#{pa}"
  #       pp "#"*200
  #       pp response
  #       if ! response.valid_encoding?
  #         response = response.encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8')
  #       end
  #       response = response.force_encoding("utf-8").gsub(" ","").gsub("vartableData=(","").gsub(");","").gsub("null",'0')
  #       response = JSON.parse response
  #       response.each do |x|
  #         fuzhai_data << x
  #       end
  #     end
  #     fuzhai_data = fuzhai_data.transpose
  #     category = ''
  #     fuzhai_data.each_with_index do |row, index|
  #       next if row[0] == '报告期' || row[0] == "币种" || row[0] == '报表类型'
  #       row[0] = "其他_#{index}" if row[0].blank? # 空白处理
  #       if row[1].blank? && row[2].blank? # 暂存目录
  #         category = row[0]
  #         next
  #       elsif row[0].include?('一、') || row[0].include?('二、') || row[0].include?('三、') || row[0].include?('四、') || row[0].include?('五、') || row[0].include?('六、') || row[0].include?('七、') || row[0].include?('八、') || row[0].include?('九、') || row[0].include?('十、')
  #         category = row[0]
  #       end
  #       stock_data_item = StockDataItem.find_or_create_by stock_summary_id: stock_summary_id,
  #                                                         name: row[0],
  #                                                         category: category # 获得数据项名称
  #       end_col_index = row.size - 1
  #       1.upto end_col_index do |col_index|
  #         unit = '百万元'
  #         quarterly_date = fuzhai_data[0][col_index]
  #
  #         stock_data_info = StockDataInfo.where(stock_id: stock.id, stock_data_item_id: stock_data_item.id, quarterly_date: quarterly_date)
  #         StockDataInfo.create! stock_id: stock.id,
  #                               stock_data_item_id: stock_data_item.id,
  #                               quarterly_date: quarterly_date,
  #                               stock_code: stock.code,
  #                               value: row[col_index].gsub(',',''),
  #                               monetary_unit: unit,
  #                               source: '新浪财经',
  #                               url: uri if stock_data_info.blank? # 指定股票，指定季度，指定数据项  数据不存在，则写数据到数据库
  #       end
  #
  #     end
  #
  #
  #
  #
  #
  #     stock_summary_id = StockSummary.find_or_create_by(name: '利润表').id
  #     lirun_data = []
  #     lirun_item_name_arr = []
  #     lirun_body_content =  doc.xpath("//tbody").select{|x|x.to_s.include?("tableGetFinanceStatus")}[0] # 利润
  #     trs_content_doc = Nokogiri::HTML(lirun_body_content.to_s)
  #     trs_content_doc.xpath("//tr").each do |tr| # 获取数据抬头
  #       td_doc = Nokogiri::HTML tr.to_s
  #       td_slop = Nokogiri::Slop td_doc.xpath("//th")[0].to_s.encode("utf-8")
  #       lirun_item_name_arr << td_slop.th.content
  #     end
  #     lirun_data << lirun_item_name_arr
  #     pp lirun_item_name_arr
  #     pp "抬头数目：#{lirun_item_name_arr.size}"
  #     params_get.each do |pa| # 获取利润数据
  #       pp "http://stock.finance.sina.com.cn/hkstock/api/jsonp.php/var%20tableData%20=%20/FinanceStatusService.getFinanceStatusForjs?symbol=#{stock.code}&financeStatus=#{pa}"
  #       response = RestClient.get "http://stock.finance.sina.com.cn/hkstock/api/jsonp.php/var%20tableData%20=%20/FinanceStatusService.getFinanceStatusForjs?symbol=#{stock.code}&financeStatus=#{pa}"
  #       if ! response.valid_encoding?
  #         response = response.encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8')
  #       end
  #       response = response.force_encoding("utf-8").gsub(" ","").gsub("vartableData=(","").gsub(");","").gsub("null",'0')
  #       response = JSON.parse response
  #       response.each do |x|
  #         lirun_data << x
  #       end
  #     end
  #     lirun_data = lirun_data.transpose
  #     category = ''
  #     lirun_data.each_with_index do |row, index|
  #       next if row[0] == '报告期' || row[0] == "币种" || row[0] == '报表类型'
  #       row[0] = "其他_#{index}" if row[0].blank? # 空白处理
  #       if row[1].blank? && row[2].blank? # 暂存目录
  #         category = row[0]
  #         next
  #       elsif row[0].include?('一、') || row[0].include?('二、') || row[0].include?('三、') || row[0].include?('四、') || row[0].include?('五、') || row[0].include?('六、') || row[0].include?('七、') || row[0].include?('八、') || row[0].include?('九、') || row[0].include?('十、')
  #         category = row[0]
  #       end
  #       stock_data_item = StockDataItem.find_or_create_by stock_summary_id: stock_summary_id,
  #                                                         name: row[0],
  #                                                         category: category # 获得数据项名称
  #       end_col_index = row.size - 1
  #       1.upto end_col_index do |col_index|
  #         unit = '百万元'
  #         quarterly_date = lirun_data[0][col_index]
  #
  #         stock_data_info = StockDataInfo.where(stock_id: stock.id, stock_data_item_id: stock_data_item.id, quarterly_date: quarterly_date)
  #         StockDataInfo.create! stock_id: stock.id,
  #                               stock_data_item_id: stock_data_item.id,
  #                               quarterly_date: quarterly_date,
  #                               stock_code: stock.code,
  #                               value: row[col_index].gsub(',',''),
  #                               monetary_unit: unit,
  #                               source: '新浪财经',
  #                               url: uri if stock_data_info.blank? # 指定股票，指定季度，指定数据项  数据不存在，则写数据到数据库
  #       end
  #
  #     end
  #
  #
  #
  #
  #
  #     stock_summary_id = StockSummary.find_or_create_by(name: '现金流量表').id
  #     xianjin_data = []
  #     xianjin_item_name_arr = []
  #     xianjin_body_content =  doc.xpath("//tbody").select{|x|x.to_s.include?("tableGetCashFlow")}[0] # 现金
  #     trs_content_doc = Nokogiri::HTML(xianjin_body_content.to_s)
  #     trs_content_doc.xpath("//tr").each do |tr| # 获取数据抬头
  #       td_doc = Nokogiri::HTML tr.to_s
  #       td_slop = Nokogiri::Slop td_doc.xpath("//th")[0].to_s.encode("utf-8")
  #       xianjin_item_name_arr << td_slop.th.content
  #     end
  #     xianjin_data << xianjin_item_name_arr
  #     pp xianjin_item_name_arr
  #     pp "抬头数目：#{xianjin_item_name_arr.size}"
  #     params_get.each do |pa| # 获取现金数据
  #       pp "http://stock.finance.sina.com.cn/hkstock/api/jsonp.php/var%20tableData%20=%20/FinanceStatusService.getCashFlowForjs?symbol=#{stock.code}&cashFlow=#{pa}"
  #       response = RestClient.get "http://stock.finance.sina.com.cn/hkstock/api/jsonp.php/var%20tableData%20=%20/FinanceStatusService.getCashFlowForjs?symbol=#{stock.code}&cashFlow=#{pa}"
  #       if ! response.valid_encoding?
  #         response = response.encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8')
  #       end
  #       response = response.force_encoding("utf-8").gsub(" ","").gsub("vartableData=(","").gsub(");","").gsub("null",'0')
  #       response = JSON.parse response
  #       response.each do |x|
  #         xianjin_data << x
  #       end
  #     end
  #     xianjin_data = xianjin_data.transpose
  #     category = ''
  #     xianjin_data.each_with_index do |row, index|
  #       next if row[0] == '报告期' || row[0] == "币种" || row[0] == '报表类型'
  #       row[0] = "其他_#{index}" if row[0].blank? # 空白处理
  #       if row[1].blank? && row[2].blank? # 暂存目录
  #         category = row[0]
  #         next
  #       elsif row[0].include?('一、') || row[0].include?('二、') || row[0].include?('三、') || row[0].include?('四、') || row[0].include?('五、') || row[0].include?('六、') || row[0].include?('七、') || row[0].include?('八、') || row[0].include?('九、') || row[0].include?('十、')
  #         category = row[0]
  #       end
  #       stock_data_item = StockDataItem.find_or_create_by stock_summary_id: stock_summary_id,
  #                                                         name: row[0],
  #                                                         category: category # 获得数据项名称
  #       end_col_index = row.size - 1
  #       1.upto end_col_index do |col_index|
  #         unit = '百万元'
  #         quarterly_date = xianjin_data[0][col_index]
  #
  #         stock_data_info = StockDataInfo.where(stock_id: stock.id, stock_data_item_id: stock_data_item.id, quarterly_date: quarterly_date)
  #         StockDataInfo.create! stock_id: stock.id,
  #                               stock_data_item_id: stock_data_item.id,
  #                               quarterly_date: quarterly_date,
  #                               stock_code: stock.code,
  #                               value: row[col_index].gsub(',',''),
  #                               monetary_unit: unit,
  #                               source: '新浪财经',
  #                               url: uri if stock_data_info.blank? # 指定股票，指定季度，指定数据项  数据不存在，则写数据到数据库
  #       end
  #
  #     end
  #
  #   end
  # end

  # 获得所有港股名称与代码
  def self.get_all_hk_stock_code_name
    table_arr = []
    1.upto 39 do |page|
      response = RestClient.get "http://q.10jqka.com.cn/interface/hk/data/gg/zdf/desc/#{page}", {
          "Host"=> "q.10jqka.com.cn",
          "User-Agent"=> "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.11; rv:42.0) Gecko/20100101 Firefox/42.0",
          "Accept"=>"application/json, text/javascript, */*; q=0.01",
          "Accept-Language"=>"zh-CN,zh;q=0.8,en-US;q=0.5,en;q=0.3",
          "Accept-Encoding"=>"gzip, deflate",
          "X-Requested-With"=>" XMLHttpRequest",
          "Referer"=>"http://q.10jqka.com.cn/hk/gg/",
          "Cookie:"=>"oncern=a%3A1%3A%7Bs%3A6%3A%22hk%2Fgg%2F%22%3Bs%3A24%3A%22%25CB%25F9%25D3%25D0%25B8%25DB%25B9%25C9%22%3B%7D; Hm_lvt_78c58f01938e4d85eaf619eae71b4ed1=1463547913; Hm_lpvt_78c58f01938e4d85eaf619eae71b4ed1=1463550075; Hm_lvt_ab89213e83c551bf095446c08bf64988=1463547913; Hm_lpvt_ab89213e83c551bf095446c08bf64988=1463550072",
          "Connection"=>"keep-alive"}


      response = JSON.parse response
      doc = Nokogiri::HTML(response["data"])

      doc.xpath("//tr").each do |tr|
        tr_doc = Nokogiri::HTML(tr.to_s)
        tds = tr_doc.xpath("//td")
        row_arr = []
        td_slop = Nokogiri::Slop tds[1].to_s.encode("utf-8").gsub("HK", "0")
        row_arr << td_slop.td.content
        td_slop = Nokogiri::Slop tds[2].to_s.encode("utf-8")
        row_arr << td_slop.td.content
        table_arr << row_arr
      end
    end
    table_arr .each do |st|
      Stock.find_or_create_by! code: st[0], name: st[1], stock_type: 2
    end
    table_arr.size
  end


  def self.get_all_usa_stock_code_name
    # self.transaction do
      1.upto 150 do |page|
        uri = "http://stock.finance.sina.com.cn/usstock/api/jsonp.php/IO.XSRV2.CallbackList%5B'doRC9iO10SZezYVc'%5D/US_CategoryService.getList?page=#{page}&num=60&sort=&asc=0&market=&id="
        result = open(uri).read
        result = result[result.index("data:")+5, result.size]
        result = result.gsub("}));","")
        result = result.gsub("{","{\"").gsub("null","\"\"").gsub(":","\":").gsub("\",", "\",\"")
        result = JSON.parse result
        result.each do |st|
          stock = Stock.where code: st["symbol"], name: st["cname"], abc: st["name"], stock_type: 3
          Stock.create! code: st["symbol"], name: st["cname"], abc: st["name"], industry_name: st["category"], stock_type: 3 if stock.blank?
        end
      end
    # end
  end

  # def self.download_a_stock is_first_download
  #
  #   stock = Stock.first
  #   url = "http://money.finance.sina.com.cn/corp/go.php/vDOWN_BalanceSheet/displaytype/4/stockid/#{stock.code}/ctrl/all.phtml"
  #   stock_summary = StockSummary.find_or_create_by name: '资产负债表'
  #   tmp_file_path = ''
  #
  #   open(url) do |fin| # 下载文件
  #     size = fin.size
  #     download_size = 0
  #     puts "size: #{size}"
  #     filename = "a_fuzhai_#{stock.code}.xls"
  #     puts "name: #{filename}"
  #     tmp_file_path = Rails.root.join('tmp', filename)
  #     open(tmp_file_path, "wb") do |fout|
  #       while buf = fin.read(1024) do
  #         fout.write buf
  #         download_size += 1024
  #         #sleep(0.5)
  #         print "Downloaded #{download_size * 100 / size}%\r"
  #         STDOUT.flush
  #       end
  #     end
  #   end
  #
  #
  #   Spreadsheet.client_encoding = 'UTF-8'
  #   book = Spreadsheet.open tmp_file_path #读取excel文件
  #   sheet = book.worksheet 0
  #   row_index = 2
  #   category = ''
  #   sheet.each 2 do |row|
  #     row[0] = "其他_#{row_index}" if row[0].blank? # 空白处理
  #     if row[1].blank? && row[2].blank? # 暂存目录
  #       category = row[0]
  #       next
  #     end
  #     stock_data_item = StockDataItem.find_or_create_by stock_summary_id: stock_summary.id,
  #                                     name: row[0],
  #                                     category: category # 获得数据项名称
  #     end_col_index = 1
  #     while !row[end_col_index].blank?
  #       end_col_index += 1
  #     end
  #     end_col_index -= 1 # 确定最后一列
  #
  #     1.upto end_col_index do |col_index|
  #       unit = sheet.row(1)[col_index]
  #       quarterly_date = sheet.row(0)[col_index]
  #       if !is_first_download # 不是第一次下载，跳过之前下载过的季度数据
  #         sds = StockDataInfo.where(stock_id: stock.id, quarterly_date: quarterly_date)
  #         next unless sds.blank?
  #       end
  #
  #       stock_data_info = StockDataInfo.where(stock_id: stock.id, stock_data_item_id: stock_data_item.id, quarterly_date: quarterly_date)
  #       StockDataInfo.create! stock_id: stock.id,
  #                             stock_data_item_id: stock_data_item.id,
  #                             quarterly_date: quarterly_date,
  #                             stock_code: stock.code,
  #                             value: row[col_index],
  #                             monetary_unit: unit,
  #                             source: '新浪财经',
  #                             url: url if stock_data_info.blank? # 指定股票，指定季度，指定数据项  数据不存在，则写数据到数据库
  #     end
  #
  #     row_index += 1
  #   end
  #
  #   File.delete tmp_file_path
  # end

end

__END__


  # Stock.list_sz_data
  def self.list_sz_data
    # 每次请求100个股票
    str = ""

    Stock::SZ.each_with_index do |code, i|
      i = i+1
      code = code.strip
      str = "#{str},sz#{code}"
      if i%100 == 0
        url = "http://hq.sinajs.cn/list=#{str}"
        pp url
        response = RestClient.get url
        ec = Encoding::Converter.new("gb18030", "UTF-8")
        content = ec.convert response.body
        content.split(';').each do |stock_info|

          stock_info.gsub!('var ', '')
          next if stock_info.blank?
          values = eval(stock_info)
          pp values
          pp 'xxxxxxx'
          next if values.blank?
          values = values.split(',')
          k = stock_info.match /hq_str_sz(\d{6})/
          Stock.create_stock name: values[0],
                             code: k[1],
                             current_price: values[3],
                             city_name: 'sz'

        end

        str = ''
      end

    end
  end



  # Stock.list_sh_data
  def self.list_sh_data

    # 每次请求100个股票
    str = ""

    (600000..603998).each_with_index do |code, i|
      code  = code.to_s
      i = i+1
      code = code.strip
      str = "#{str},sh#{code}"
      if i%300 == 0
        url = "http://hq.sinajs.cn/list=#{str}"
        pp url
        response = RestClient.get url
        ec = Encoding::Converter.new("gb18030", "UTF-8")
        content = ec.convert response.body
        content.split(';').each do |stock_info|

          stock_info.gsub!('var ', '')
          next if stock_info.blank?
          values = eval(stock_info)
          pp values
          pp 'xxxxxxx'
          next if values.blank?
          values = values.split(',')
          k = stock_info.match /hq_str_sh(\d{6})/
          Stock.create_stock name: values[0],
                             code: k[1],
                             current_price: values[3],
                             city_name: 'sh'

        end
        str = ''
      end
    end

    def self.create_stock options
    stock = Stock.where(code: options[:code]).first
    if stock.blank?
      s = Stock.new name: options[:name],
                    code: options[:code],
                    current_price: ((options[:current_price].to_f)*100).to_i,
                    city_name: options[:city_name]
      s.save!
    else
      stock.current_price = ((options[:current_price].to_f)*100).to_i
      stock.save!
    end
  end
  end


  while true
    begin
      Stock.init_get_all_a_stock_info_from_sina true
    rescue Exception => e
      pp 'error restart'
    end
  end


  while true
    begin
  skip_has_downloaded = true
      Stock.where("id <= 2409 and id >").each do |stock|
          self.transaction do
            next if skip_has_downloaded && stock.download_times>=1
            StockSummary.all.each do |stock_summary|
              get_a_stock_info_from_sina stock.id, stock_summary.id, year
            end
            stock.download_times += 1
            stock.save!
          end
        end

    rescue Exception => e

    end
  end