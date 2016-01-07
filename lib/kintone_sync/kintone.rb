module KintoneSync
  class Kintone
    def initialize(app_id=nil)
      host = ENV['KINTONE_HOST']
      user = ENV['KINTONE_USER']
      pass = ENV['KINTONE_PASS']
      @app_id = app_id
      @api = ::Kintone::Api.new(host, user, pass)
    end

    def self.app_create!(name, fields=nil)
      k = self.new
      @api = k.api
      # https://github.com/pandeiro245/kintone/pull/1/files
      # https://github.com/pandeiro245/kintone_sync/issues/17#issuecomment-168527270
      # k.api.app.register(name, fields)

      url = '/k/v1/preview/app.json'
      res = @api.post(url, name:name)
      app = res['app'].to_i
      k.app(app).create_fields(fields) if fields
      k.deploy
      return {app: app, name: name}
    end

    def create_fields fields
      url = '/k/v1/preview/app/form/fields.json'
      params = {app: @app_id, properties: fields}

      res = @api.post(url, params)
      puts res.inspect
      raise if res['errors']
    end

    def update_fields fields
      url = '/k/v1/preview/app/form/fields.json'
      params = {app: @app_id, properties: fields}

      res = @api.put(url, params)
      puts res.inspect
      raise if res['errors']
    end

    def delete_field field_name
      url = '/k/v1/preview/app/form/fields.json'
      params = {app: @app_id, fields: [field_name]}
      res = @api.delete(url, params)
      puts res.inspect
      raise if res['errors']
      res
    end

    def deploy
      sec = 5
      url = '/k/v1/preview/app/deploy.json'
      res = @api.post(url, apps:[{app: @app_id}])

      if res['code'] && res['code'] == 'GAIA_APD02'
        # 設定を運用環境に適用する処理、または設定をキャンセルする処理をすでに実行中です。
        puts  "sleep #{sec}sec..."
        sleep sec
        deploy
      end
      raise res.inspect if res['errors']
      puts "deploy is done! & sleep #{sec}sec..."
      sleep sec

      res
    end

    def self.remove(app_id)
      self.new(app_id).remove
    end

    def api
      @api
    end

    def find id
      @api.record.get(@app_id, id)['record']
    end

    def app(app_id)
      @app_id = app_id
      self
    end

    def all
      res = []
      offset = 0
      query = "offset #{offset}"
      items = @api.records.get(@app_id, query, [])
      while(items['records'].present?)
        res += items['records']
        offset += items['records'].count
        query = "offset #{offset}"
        items = @api.records.get(@app_id, query, [])
      end
      res
    end

    def where cond
      query = ''
      cond.each do |k, v|
        query += "#{k} = \"#{v.to_s}\""
      end
      @api.records.get(@app_id, query, [])
    end

    def save pre_params, unique_key=nil
      if unique_key
        cond = {}
        cond[unique_key] = pre_params[unique_key]
        records = where(cond)['records']
        if records.present?
          id = records.first['$id']['value'].to_i
          return update(id, pre_params)
        end
      end
      create(pre_params)
    end

    def create pre_params
      params = {}
      pre_params.each do |k, v|
        params[k] = {value: v}
      end
      begin
        res = @api.record.register(@app_id, params)
      rescue
        sleep 5
        save pre_params
      end
      res
    end

    def save! record, unique_key=nil
      res = save(record, unique_key)
      res['message'] ? raise(res.inspect) : res
    end

    def update id, record
      params = {}
      record.each do |k, v|
        params[k] = {value: v}
      end
      @api.record.update(@app_id, id.to_i, params)
    end

    def update! id, record
      res = update(id, record)
      res['message'] ? raise(res.inspect) : res
    end


    def calculate params
      logic = params[:logic]
      column_name = params[:column_name]
      puts "logic is #{logic}"
      all.each do |record|
        case logic
        when 'absolute'
          from_column_name='amount'
          to_column_name='amount_absolute'
          params[to_column_name] = record[from_column_name]['value'].to_i.abs
        when 'blank_is_forever'
          next if record[column_name]['value'].present?
          params[column_name] = '3000-01-01'
        end
        id = record['$id']['value']
        update(id, params)
      end
    end

    def remove app_id=nil
      app_id ||= @app_id
      # 500以上にしたらエラーになる
      # 削除が一度に100件しかできない）
      query = 'limit 100' 
      records = @api.records.get(app_id, query, [])['records']
      is_retry = true if records.present? && records.count >= 100
      return 'no records' if records.blank?
      ids = records.map{|r| r['$id']['value'].to_i}
      puts 'start to delete'
      @api.records.delete(app_id, ids)
      puts 'end to delete'
      remove if is_retry
    end
  end
end
