class Stock < ActiveRecord::Base

  has_many :stock_data_infos
  has_many :assessments

  require 'rest-client'
  require 'pp'
  require 'nokogiri'
  require 'open-uri'
  require 'csv'

  CN_US_STOCKS = ["BSPM", "CNR", "RENN", "JMEI", "CCCR", "YGE", "CGA", "YRD", "BORN", "EFUT", "HOLI", "HIMX", "CPHI", "SFUN", "CLNT", "JRJC", "MOMO", "AUO", "CYD", "CSIQ", "SIMO", "DSWL", "XNY", "NFEC", "SPIL", "NTES", "DANG", "ACTS", "LITB", "JKS", "TSM", "GIGM", "NQ", "CNIT", "CCM", "SOL", "IMOS", "JASO", "UMC", "HPJ", "QIHU", "TSL", "LEJU", "CXDC", "CYOU", "SOHU", "KGJI", "LFC", "TOUR", "DQ", "CHU", "CCCL", "CTRP", "TAOM", "IDI", "SMI", "JD", "CISG", "CHL", "KNDI", "ASX", "JOBS", "SNP", "HTHT", "CEA", "EDU", "ZNH", "CHA", "TEDU", "HNP", "CAAS", "CBPO", "BIDU", "RCON", "GSH", "APWC", "CEO", "FENG", "CADC", "AMC", "XRS", "YY", "SHI", "CHT", "BABA", "YIN", "ATV", "MPEL", "GSOL", "CNTF", "EHIC", "NPD", "PTR", "SINA", "JFC", "FFHL", "LONG", "HIHO", "ALMMF", "AMCF", "CALI", "CCGM", "CCSC", "CDII", "CHGS", "CHLN", "CHOP", "CJJD", "CLWT", "CMFO", "CNYD", "CO", "CPGI", "CPSL", "CSUN", "CTC", "CYDI", "DION", "DL", "EDS", "EGT", "EJ", "GAI", "GOAS", "GPRC", "GRO", "HEAT", "JP", "JST", "KEYP", "KUTV", "LAS", "LIWA", "MY", "NDAC", "NED", "NTE", "OIIM", "QKLS", "SCOK", "SKBI", "SORL", "SUTR", "SVA", "THTI", "TPI", "VALV", "ZA", "ZOOM", "ZX", "KZ", "XIN", "YZC", "VNET", "ACH", "VIPS", "XUE", "WB", "UTSI", "XNET", "MOBI", "CHNR", "SSW", "ATHM", "WUBA", "ALN", "GSI", "KANG", "NCTY", "ZPIN", "AMCN", "SEED", "SYUT", "GURE", "QUNR", "SGOC", "SKYS", "WBAI", "BITA", "ONP", "CREG", "VISN", "HGSH", "CCIH", "CNET", "STV", "EVK", "KONE", "BNSO", "CBAK", "NOAH", "DHRM", "LEDS", "WOWO", "SPU", "ATAI", "CMCM", "SINO", "OSN"]

  MONEY_UNIT = {
      1 => 'M RMB',
      2 => 'M RMB',
      3 => 'M USD',
  }

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

      t_stock_data_item_id = stock_summary.stock_data_items.first.id rescue ''
      unless t_stock_data_item_id.blank?
        t_stock_data_info = StockDataInfo.where(stock_id: stock_id, stock_data_item_id: t_stock_data_item_id).where("quarterly_date in (?) ", ["#{year}-03-31", "#{year}-06-30", "#{year}-09-30", "#{year}-12-31"])

        unless t_stock_data_info.blank? # 如果此股、此类型、此年份数据已经抓过，就跳过
          pp '存在，跳过'
          return
        end
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
        next if skip_has_downloaded && stock.download_times>=1
        StockSummary.all.each do |stock_summary|
          self.get_hk_stock_info_from_sina stock.id, stock_summary.id
        end
        stock.download_times += 1
        stock.save!
    end
  end


  def self.get_all_hk_stock_info_from_sina_between start_id, end_id, skip_has_downloaded=false
    Stock.where("id >= ? and id <= ?", start_id, end_id).each do |stock|
      next if skip_has_downloaded && stock.download_times>=1
      StockSummary.all.each do |stock_summary|
        self.get_hk_stock_info_from_sina stock.id, stock_summary.id
      end
      stock.download_times += 1
      stock.save!
    end
  end


  # 从新浪获得某只港股的财务信息
  def self.get_hk_stock_info_from_sina stock_id, stock_summary_id
    self.transaction do


    params_get = ['zero', '1', '2', '3']
    stock_summary = StockSummary.find(stock_summary_id)
    stock = Stock.find(stock_id)

    pp "##"*50
    pp "stock_id:#{stock.id} name:#{stock.name} stock_summary_id:#{stock_summary.name}   "

    t_stock_data_item_id = stock_summary.stock_data_items.ids rescue ''
    unless t_stock_data_item_id.blank?
      t_stock_data_info = StockDataInfo.where(stock_id: stock_id).where("stock_data_item_id in (?)", t_stock_data_item_id)

      unless t_stock_data_info.blank? # 如果此股、此类型已经抓过，就跳过
        pp '存在，跳过'
        return
      end
    end


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





    uri = "http://stock.finance.sina.com.cn/hkstock/finance/#{stock.code}.html"
    # doc = Nokogiri::HTML(open(uri).read.force_encoding('GBK').encode("utf-8"))
    response = RestClient.get uri
    ec = Encoding::Converter.new("GBK", "UTF-8")
    doc = ec.convert response.body
    doc = Nokogiri::HTML(doc)
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
    # pp sub_item_name_arr
    # pp "抬头数目：#{sub_item_name_arr.size}"
    params_get.each do |pa| # 获取负债数据
      # pp pa
      # pp "获取负债数据"
      pp uri
      pp "http://stock.finance.sina.com.cn/hkstock/api/jsonp.php/var%20tableData%20=%20/FinanceStatusService.#{url_pa}?symbol=#{stock.code}&#{url_pa2}=#{pa}"
      response = RestClient.get "http://stock.finance.sina.com.cn/hkstock/api/jsonp.php/var%20tableData%20=%20/FinanceStatusService.#{url_pa}?symbol=#{stock.code}&#{url_pa2}=#{pa}"
      # pp "#"*200
      # pp response
      if ! response.valid_encoding?
        response = response.encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8')
      end
      response = response.force_encoding("utf-8").gsub(" ","").gsub("vartableData=(","").gsub(");","")
      next if response.blank? || response == 'null'
      response = response.gsub("null","\"--\"")
      # pp "response: "
      # pp response
      response = JSON.parse response
      row_size = total_data[0].size
      response.each do |x|
        return if row_size > x.size
        total_data << x[0..row_size-1]
      end
      # pp 'total_data last:'
      # pp total_data
    end

    # pp 'total_data before transpose:'
    # pp total_data
    total_data = total_data.transpose
    # pp "total_data after transpose:"
    # pp total_data
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
                              value: row[col_index],
                              monetary_unit: unit,
                              source: '新浪财经',
                              url: uri if stock_data_info.blank? # 指定股票，指定季度，指定数据项  数据不存在，则写数据到数据库
      end

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

  # 从雅虎获得所有中概股的年报财务信息
  def self.get_all_cn_usa_stocks_info_from_yahoo skip_has_downloaded=false
    Stock.where(stock_type: 3).where("code in (?) ", self::CN_US_STOCKS).each do |stock|
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

  # 指定id区间从雅虎下载美股年报财务信息
  # Stock.get_usa_stocks_info_from_yahoo_between 1, 100
  def self.get_usa_stocks_info_from_yahoo_between start_id, end_id, skip_has_downloaded=false
    Stock.where(stock_type: 3).where("id>= ? and id < ?", start_id, end_id).each do |stock|
      begin
        self.transaction do
          next if skip_has_downloaded && stock.download_times>=1
          StockSummary.all.each do |stock_summary|
            self.get_usa_stock_info_from_yahoo stock.id, stock_summary.id
          end
          stock.download_times += 1
          stock.save!
        end
      rescue Exception => e

      end
    end
  end

  # 从雅虎获得所有美股的年报财务信息
  # Stock.get_all_usa_stocks_info_from_yahoo
  def self.get_all_usa_stocks_info_from_yahoo skip_has_downloaded=false
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
                      "http://finance.yahoo.com/q/bs?s=#{stock.code}&annual"
                    when '利润表'
                      "http://finance.yahoo.com/q/is?s=#{stock.code}&annual"
                    when '现金流量表'
                      "http://finance.yahoo.com/q/cf?s=#{stock.code}&annual"
                  end
      # doc = Nokogiri::HTML(open(uri).read.encode("utf-8"))

      response = RestClient.get uri
      ec = Encoding::Converter.new("GBK", "UTF-8")
      doc = ec.convert response.body
      doc = Nokogiri::HTML(doc)

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

  # 批量生成fcf
  # Stock.generate_fcf_of_stock_id_between 1, 2, true
  def self.generate_fcf_of_stock_id_between start_id, end_id, skip_existed=false
    Stock.where("id>= ? and id < ?", start_id, end_id).each do |stock|
      begin
          end_year = 2015
          start_year = stock.stock_type == 3 ? 2013 : 2011
          price = StockMarketHistory.where(stock_id: stock.id).order(trade_date: :desc).limit(1).first
          raise "股票#{stock.id} #{stock.code} #{stock.name} 没有任何交易价格" if price.blank?
          date = price.trade_date
          version = 100
          Stock.transaction do
            stock.generate_fcf start_year, end_year, date, version, skip_existed
          end
      rescue Exception => e
        CSV.open(Rails.root.join("tmp/log.csv").to_s, "ab") do |csv|
          csv << [stock.code.to_s, stock.name.to_s, e.to_s]
        end
      end
    end
  end


  def generate_fcf start_year, end_year, date, version, skip_existed=false

    Stock.transaction do
      assessments = Assessment.where(stock_id: id, base_on_year: end_year, early_boundary_year: start_year, delete_flag: 0)
      return if skip_existed && !assessments.blank?
      assessments.each do |a|
        a.delete_flag = 1
        a.save!
      end
      assessment = Assessment.new stock_id: id,
                     base_on_year: end_year,
                     early_boundary_year: start_year,
                     algorithm_name: version,
                     delete_flag: 0
      assessment.save!

      assessment.base_on_year.to_i.downto assessment.early_boundary_year.to_i do |year|
        AnalysisType.used.with_year.each do |analysis_type|
          raise "#{analysis_type.name}的计算函数为空" if analysis_type.blank?
          # p_num = self.method(analysis_type.calc_expression.to_sym).arity
          ps = self.method(analysis_type.calc_expression.to_sym).parameters.collect{|x|x.last}
          val = if ps == [:year, :version]
                  self.__send__ analysis_type.calc_expression, year, version
                elsif ps == [:start_year, :end_year, :version]
                  self.__send__ analysis_type.calc_expression, assessment.early_boundary_year, assessment.base_on_year, version
                elsif ps == [:version]
                  self.__send__ analysis_type.calc_expression, version
                elsif ps == [:date, :version]
                  self.__send__ analysis_type.calc_expression, date, version
                elsif ps == [:start_year, :end_year, :date, :version]
                  self.__send__ analysis_type.calc_expression, assessment.early_boundary_year, assessment.base_on_year, date, version
                elsif ps == [:year, :start_year, :version]
                  self.__send__ analysis_type.calc_expression, year, assessment.early_boundary_year, version
                end
          item = AssessmentItem.new year: year,
                                     analysis_type_id: analysis_type.id,
                                     assessment_id: assessment.id,
                                     money_unit: Stock::MONEY_UNIT[stock_type],
                                     value: val
          item.save!
        end
      end

      AnalysisType.used.without_year.each do |analysis_type|
        raise "#{analysis_type.name}的计算函数为空" if analysis_type.blank?
        # p_num = self.method(analysis_type.calc_expression.to_sym).arity
        ps = self.method(analysis_type.calc_expression.to_sym).parameters.collect{|x|x.last}
        val = if ps == [:year, :version]
                self.__send__ analysis_type.calc_expression, assessment.base_on_year, version
              elsif ps == [:start_year, :end_year, :version]
                self.__send__ analysis_type.calc_expression, assessment.early_boundary_year, assessment.base_on_year, version
              elsif ps == [:version]
                self.__send__ analysis_type.calc_expression, version
              elsif ps == [:date, :version]
                self.__send__ analysis_type.calc_expression, date, version
              elsif ps == [:start_year, :end_year, :date, :version]
                self.__send__ analysis_type.calc_expression, assessment.early_boundary_year, assessment.base_on_year, date, version
              elsif ps == [:year, :start_year, :version]
                self.__send__ analysis_type.calc_expression, assessment.base_on_year, assessment.early_boundary_year, version
              end
        item = AssessmentItem.new year: assessment.base_on_year,
                                  analysis_type_id: analysis_type.id,
                                  assessment_id: assessment.id,
                                  money_unit: Stock::MONEY_UNIT[stock_type],
                                  value: val
        item.save!
      end

    end
  end

  #************************* 动态调用 ⬇️ **************************************

  def calc_revenue year, version
    self.__send__ "calc_revenue_#{version}", year
  end

  def calc_COGS year, version
    self.__send__ "calc_COGS_#{version}", year
  end

  def calc_SGA year, version
    self.__send__ "calc_SGA_#{version}", year
  end

  def calc_other_costs year, version
    self.__send__ "calc_other_costs_#{version}", year
  end

  def calc_EBIT year, version
    self.__send__ "calc_EBIT_#{version}", year
  end

  def calc_work_capital year, version
    self.__send__ "calc_work_capital_#{version}", year
  end

  def calc_balance_cash year, version
    self.__send__ "calc_balance_cash_#{version}", year
  end

  def calc_inventory year, version
    self.__send__ "calc_inventory_#{version}", year
  end

  def calc_receivables year, version
    self.__send__ "calc_receivables_#{version}", year
  end

  def calc_payables year, version
    self.__send__ "calc_payables_#{version}", year
  end

  def calc_interest_bearing_debts year, version
    self.__send__ "calc_interest_bearing_debts_#{version}", year
  end

  def calc_short_term_loans year, version
    self.__send__ "calc_short_term_loans_#{version}", year
  end

  def calc_long_term_loans year, version
    self.__send__ "calc_long_term_loans_#{version}", year
  end

  def calc_bill_payable year, version
    self.__send__ "calc_bill_payable_#{version}", year
  end

  def calc_NOPLAT year, version
    self.__send__ "calc_NOPLAT_#{version}", year
  end

  def calc_depreciation_and_amortization year, version
    self.__send__ "calc_depreciation_and_amortization_#{version}", year
  end

  def calc_increase_in_working_capital year, start_year, version
    self.__send__ "calc_increase_in_working_capital_#{version}", year, start_year
  end

  def calc_CAPEX year, version
    self.__send__ "calc_CAPEX_#{version}", year
  end

  def calc_FCF year, start_year, version
    self.__send__ "calc_FCF_#{version}", year, start_year
  end



  def calc_average_FCF start_year, end_year, version
    self.__send__ "calc_average_FCF_#{version}", start_year, end_year
  end

  def calc_average_incr_in_working_capital start_year, end_year, version
    self.__send__ "calc_average_incr_in_working_capital_#{version}", start_year, end_year
  end

  def calc_average_CAPEX start_year, end_year, version
    self.__send__ "calc_average_CAPEX_#{version}", start_year, end_year
  end

  def calc_pro_forma_FCF start_year, end_year, version
    self.__send__ "calc_pro_forma_FCF_#{version}", start_year, end_year
  end


  def calc_FCF_multiples version
    self.__send__ "calc_FCF_multiples_#{version}"
  end

  def calc_cash_rate_for_NOPLAT version
    self.__send__ "calc_cash_rate_for_NOPLAT_#{version}"
  end

  def calc_exchange_rate version
    self.__send__ "calc_exchange_rate_#{version}"
  end

  def calc_ennterprise_value start_year, end_year, version
    self.__send__ "calc_ennterprise_value_#{version}", start_year, end_year
  end

  def calc_interesting_bearing_debts year, version
    self.__send__ "calc_interesting_bearing_debts_#{version}", year
  end

  def calc_valuation_cash year, version
    self.__send__ "calc_valuation_cash_#{version}", year
  end

  def calc_equity_value start_year, end_year, version
    self.__send__ "calc_equity_value_#{version}", start_year, end_year
  end

  def calc_shares_outstanding year, version
    self.__send__ "calc_shares_outstanding_#{version}", year
  end

  def calc_ADR_to_stock_ratio version
    self.__send__ "calc_ADR_to_stock_ratio_#{version}"
  end

  def calc_per_share_value start_year, end_year, version
    self.__send__ "calc_per_share_value_#{version}", start_year, end_year
  end

  def calc_current_stock_price date, version
    self.__send__ "calc_current_stock_price_#{version}", date
  end

  def calc_premium_by_discount start_year, end_year, date, version
    self.__send__ "calc_premium_by_discount_#{version}", start_year, end_year, date
  end


  #************************* 动态调用 ⬆️️ **************************************

  def get_annual_info_by_item_name_and_year item_name, year
  # stock_data_infos = StockDataInfo.where(stock_id: self.id).joins(:stock_data_item)
  #   .where("stock_data_items.name = ? ", item_name)
  #   .where("stock_data_infos.quarterly_date = ?", "#{year}-12-31")

    item_ids = StockDataItem.where(name: item_name).select('id').pluck(:id)

    stock_data_infos = StockDataInfo.where("stock_id = ? and quarterly_date = ? and stock_data_item_id in (?)", self.id, "#{year}-12-31",(item_ids))
    # sql = <<-EOF
    #   select * from  (
	   #    select * from stock_data_infos where stock_id = #{self.id} and stock_data_infos.quarterly_date = '#{year}-12-31'
    #       ) T1 left join stock_data_items on T1.stock_data_item_id = stock_data_items.id
    #     where stock_data_items.name = '#{item_name}'
    # EOF


    # stock_data_infos = StockDataInfo.find_by_sql(sql)

    excption_str = "stock_id:#{self.id},quarterly_date:#{year}-12-31,item_name:#{item_name}"
    raise "数据不存在, #{excption_str}" if stock_data_infos.blank?
    raise "数据重复, #{excption_str}" if stock_data_infos.count > 1

    stock_data_info = stock_data_infos.first

    stock_data_info.value
  end



  def calc_revenue_100 year
    case stock_type
      when 1
        value = get_annual_info_by_item_name_and_year '一、营业总收入', year
        (value/100.0).round(2)
      when 2
        (get_annual_info_by_item_name_and_year '营业额', year).round(2)
      when 3
        value = get_annual_info_by_item_name_and_year 'Total Revenue', year
        (value/1000.0).round(2)
    end

  end

  def calc_COGS_100 year
    case stock_type
      when 1
        value = get_annual_info_by_item_name_and_year '营业成本', year
        (value/100.0).round(2)
      when 2
        (get_annual_info_by_item_name_and_year '销售成本', year).round(2)
      when 3
        value = get_annual_info_by_item_name_and_year 'Cost of Revenue', year
        (value/1000.0).round(2)
    end

  end

  def calc_SGA_100 year
    case stock_type
      when 1
        value1 = get_annual_info_by_item_name_and_year '销售费用', year
        value2 = get_annual_info_by_item_name_and_year '管理费用', year
        (value1/100.0 + value2/100.0).round(2)
      when 2
        value1 = get_annual_info_by_item_name_and_year '销售及分销费用', year
        value2 = get_annual_info_by_item_name_and_year '一般及行政费用', year
        (value1 + value2).round(2)
      when 3
        value1 = get_annual_info_by_item_name_and_year 'Research Development', year
        value2 = get_annual_info_by_item_name_and_year 'Selling General and Administrative', year
        (value1/1000.0 + value2/1000.0).round(2)
    end
  end

  def calc_other_costs_100 year
    case stock_type
      when 1
        value = get_annual_info_by_item_name_and_year '资产减值损失', year
        (value/100.0).round(2)
      when 2
        0
      when 3
        value = get_annual_info_by_item_name_and_year 'Others', year
        (value/1000.0).round(2)
    end
  end

  def calc_EBIT_100 year
    case stock_type
      when 1
        (calc_revenue_100(year) - calc_COGS_100(year) - calc_SGA_100(year) - calc_other_costs_100(year)).round(2)
      when 2
        (calc_revenue_100(year) - calc_COGS_100(year) - calc_SGA_100(year) - calc_other_costs_100(year)).round(2)
      when 3
        value = get_annual_info_by_item_name_and_year 'Earnings Before Interest And Taxes', year
        (value/1000.0).round(2)
    end
  end

  def calc_work_capital_100 year
    (calc_balance_cash_100(year) + calc_inventory_100(year) + calc_receivables_100(year) - calc_payables_100(year)).round(2)
  end

  def calc_balance_cash_100 year
    case stock_type
      when 1
        value = get_annual_info_by_item_name_and_year '货币资金', year
        (value/100).round(2)
      when 2
        (get_annual_info_by_item_name_and_year '现金及银行结存(流动资产)', year).round(2)
      when 3
        value = get_annual_info_by_item_name_and_year 'Cash And Cash Equivalents', year
        (value/1000).round(2)
    end
  end

  def calc_inventory_100 year
    case stock_type
      when 1
        value = get_annual_info_by_item_name_and_year '存货', year
        (value/100).round(2)
      when 2
        (get_annual_info_by_item_name_and_year '存货(流动资产)', year).round(2)
      when 3
        value = get_annual_info_by_item_name_and_year 'Inventory', year
        (value/1000).round(2)
    end
  end

  def calc_receivables_100 year
    case stock_type
      when 1
        value1 = get_annual_info_by_item_name_and_year '应收票据', year
        value2 = get_annual_info_by_item_name_and_year '应收账款', year
        value3 = get_annual_info_by_item_name_and_year '其他应收款', year
        value4 = get_annual_info_by_item_name_and_year '预收款项', year
        ((value1 + value2 + value3 - value4)/100.0).round(2)
      when 2
        (get_annual_info_by_item_name_and_year '应收账款(流动资产)', year).round(2)
      when 3
        0
    end
  end

  def calc_payables_100 year
    case stock_type
      when 1
        value1 = get_annual_info_by_item_name_and_year '应付票据', year
        value2 = get_annual_info_by_item_name_and_year '应付账款', year
        value3 = get_annual_info_by_item_name_and_year '其他应付款', year
        value4 = get_annual_info_by_item_name_and_year '预付款项', year
        ((value1 + value2 + value3 - value4)/100.0).round(2)
      when 2
        (get_annual_info_by_item_name_and_year '应付帐款(流动负债)', year).round(2)
      when 3
        value = get_annual_info_by_item_name_and_year 'Accounts Payable', year
        (value/1000).round(2)
    end
  end

  def calc_interest_bearing_debts_100 year
    (calc_short_term_loans_100(year) + calc_long_term_loans_100(year) + calc_bill_payable_100(year)).round(2)
  end

  def calc_short_term_loans_100 year
    case stock_type
      when 1
        value = get_annual_info_by_item_name_and_year '短期借款', year
        (value/100.0).round(2)
      when 2
        (get_annual_info_by_item_name_and_year '银行贷款(流动负债)', year).round(2)
      when 3
        value1 = get_annual_info_by_item_name_and_year 'Short/Current Long Term Debt', year
        value2 = get_annual_info_by_item_name_and_year 'Long Term Debt', year
        (value1/1000.0-value2/1000).round(2)
    end
  end

  def calc_long_term_loans_100 year
    case stock_type
      when 1
        value = get_annual_info_by_item_name_and_year '长期借款', year
        (value/100.0).round(2)
      when 2
        0
      when 3
        value = get_annual_info_by_item_name_and_year 'Long Term Debt', year
        (value/1000).round(2)
    end
  end

  def calc_bill_payable_100 year
    case stock_type
      when 1
        value = get_annual_info_by_item_name_and_year '应付债券', year
        (value/100.0).round(2)
      when 2
        0
      when 3
        0
    end
  end


  def calc_NOPLAT_100 year
    (calc_EBIT_100(year)*(1-calc_cash_rate_for_NOPLAT_100)).round(2)
  end

  def calc_depreciation_and_amortization_100 year
    case stock_type
      when 1
        value1 = get_annual_info_by_item_name_and_year "资产减值准备", year
        value2 = get_annual_info_by_item_name_and_year "固定资产折旧、油气资产折耗、生产性物资折旧", year
        value3 = get_annual_info_by_item_name_and_year "无形资产摊销", year
        value4 = get_annual_info_by_item_name_and_year "长期待摊费用摊销", year
        ((value1 + value2 + value3 + value4)/100.0).round(2)
      when 2
        (get_annual_info_by_item_name_and_year '折旧', year).round(2)
      when 3
        value1 = get_annual_info_by_item_name_and_year "Depreciation", year
        (value1/1000.0).round(2)
    end
  end

  def calc_increase_in_working_capital_100 year, start_year
    case stock_type
      when 1
        if start_year == year
          value1 = get_annual_info_by_item_name_and_year "存货的减少", year
          value2 = get_annual_info_by_item_name_and_year "经营性应收项目的减少", year
          value3 = get_annual_info_by_item_name_and_year "经营性应付项目的增加", year
          ((value1 + value2 + value3)/100.0).round(2)
        else
          (calc_work_capital_100(year) - calc_work_capital_100(year.to_i-1)).round(2)
        end
      when 2
        if start_year == year
          0
        else
          (calc_work_capital_100(year) - calc_work_capital_100(year.to_i-1)).round(2)
        end

      when 3
        value1 = get_annual_info_by_item_name_and_year "Changes In Accounts Receivables", year
        value2 = get_annual_info_by_item_name_and_year "Changes In Liabilities", year
        value3 = get_annual_info_by_item_name_and_year "Changes In Inventories", year
        ((value1 + value2 + value3)/1000.0).round(2)
    end
  end

  def calc_CAPEX_100 year
    case stock_type
      when 1
        value = get_annual_info_by_item_name_and_year '购建固定资产、无形资产和其他长期资产所支付的现金', year
        (value/100.0).round(2)
      when 2
        -(get_annual_info_by_item_name_and_year '购置固定资产款项', year).round(2)
      when 3
        value = -(get_annual_info_by_item_name_and_year 'Capital Expenditures', year)
        (value/1000.0).round(2)
    end
  end

  def calc_FCF_100 year, start_year
    (calc_NOPLAT_100(year) - calc_increase_in_working_capital_100(year, start_year) - calc_CAPEX_100(year) + calc_depreciation_and_amortization_100(year)).round(2)
  end

  def calc_average_FCF_100 start_year, end_year
    start_year = start_year.to_i
    end_year = end_year.to_i
    total = 0.0
    start_year.to_i.upto end_year.to_i do |year|
      total += calc_FCF_100 year, start_year
    end
    (total/(end_year-start_year+1)).round(2)
  end

  def calc_average_incr_in_working_capital_100 start_year, end_year
    case stock_type
      when 1
        start_year = start_year.to_i
        end_year = end_year.to_i
        total = 0.0
        start_year.to_i.upto end_year.to_i do |year|
          total += calc_increase_in_working_capital_100 year, start_year
        end
        (total/(end_year-start_year+1)).round(2)
      when 2
        0.02*((calc_revenue_100 end_year) - (calc_revenue_100 end_year - 1))
      when 3
        start_year = start_year.to_i
        end_year = end_year.to_i
        total = 0.0
        start_year.to_i.upto end_year.to_i do |year|
          total += calc_increase_in_working_capital_100 year, start_year
        end
        (total/(end_year-start_year+1)).round(2)
    end

  end

  def calc_average_CAPEX_100 start_year, end_year
    start_year = start_year.to_i
    end_year = end_year.to_i
    total = 0.0
    start_year.to_i.upto end_year.to_i do |year|
      total += calc_CAPEX_100 year
    end
    (total/(end_year-start_year+1)).round(2)
  end

  def calc_pro_forma_FCF_100 start_year, end_year
    (calc_NOPLAT_100(end_year) - calc_average_incr_in_working_capital_100(start_year, end_year) - calc_average_CAPEX_100(start_year, end_year) + calc_depreciation_and_amortization_100(end_year)).round(2)
  end


  def calc_FCF_multiples_100
    case stock_type
      when 1
        10.0
      when 2
        10.0
      when 3
        10.0
    end
  end

  def calc_cash_rate_for_NOPLAT_100
    case stock_type
      when 1
        0.25
      when 2
        0.25
      when 3
        0.25
    end
  end

  def calc_exchange_rate_100
    case stock_type
      when 1
        1
      when 2
        0.84
      when 3
        6.53
    end
  end

  def calc_ennterprise_value_100 start_year, end_year
    (calc_pro_forma_FCF_100(start_year, end_year)*calc_FCF_multiples_100).round(2)
  end

  def calc_interesting_bearing_debts_100 year
    calc_interest_bearing_debts_100 year
  end

  def calc_valuation_cash_100 year
    calc_balance_cash_100 year
  end

  def calc_equity_value_100 start_year, end_year
    (calc_valuation_cash_100(end_year) + calc_ennterprise_value_100(start_year, end_year) - calc_interesting_bearing_debts_100(end_year)).round(2)
  end

  def calc_shares_outstanding_100 year
    case stock_type
      when 1
        value = get_annual_info_by_item_name_and_year '实收资本(或股本)', year
        (value/100.0).round(2)
      when 2
        ((get_annual_info_by_item_name_and_year '股份数目(香港)', year)/1000000.0).round(2)
      when 3
        value = get_annual_info_by_item_name_and_year 'Common Stock', year
        (value/1000.0).round(2)
    end
  end

  def calc_ADR_to_stock_ratio_100
    case stock_type
      when 1
        0
      when 2
        0
      when 3
        2.0
    end
  end

  def calc_per_share_value_100 start_year, end_year
    (calc_equity_value_100(start_year, end_year)/calc_shares_outstanding_100(end_year)).round(2)
  end

  def calc_current_stock_price_100 date
    price = StockMarketHistory.where(stock_id: self.id, trade_date: date.to_date).first
    raise "该股票#{self.name}没有#{date}的股价" if price.blank?
    price.close_price
  end

  def calc_premium_by_discount_100 start_year, end_year, date
    case stock_type
      when 1
        (calc_current_stock_price_100(date)/calc_per_share_value_100(start_year, end_year) - 1).round(3)
      when 2
        (calc_current_stock_price_100(date)*calc_exchange_rate_100/calc_per_share_value_100(start_year, end_year)-1).round(3)
      when 3
        (calc_current_stock_price_100(date)/calc_per_share_value_100(start_year, end_year)/calc_ADR_to_stock_ratio_100 - 1).round(3)
    end
  end

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
      Stock.init_get_all_a_stock_info_from_sina_between 1,200 true
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