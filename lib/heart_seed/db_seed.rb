module HeartSeed
  module DbSeed
    BULK = "bulk"
    ACTIVE_RECORD = "active_record"
    # delete all records and bulk insert from seed yaml
    #
    # @param source_file [String]
    # @param model_class [Class] require. extends {ActiveRecord::Base}
    def self.bulk_insert(source_file: nil, model_class: nil)
      fixtures = HeartSeed::Converter.read_fixture_yml(source_file)
      models = fixtures.each_with_object([]) do |fixture, response|
        response << model_class.new(fixture)
        response
      end

      model_class.transaction do
        model_class.delete_all
        model_class.import(models)
      end
    end

    # delete all records and insert from seed yaml
    #
    # @param source_file [String]
    # @param model_class [Class] require. extends {ActiveRecord::Base}
    def self.insert(source_file: nil, model_class: nil)
      fixtures = HeartSeed::Converter.read_fixture_yml(source_file)
      model_class.transaction do
        model_class.delete_all
        fixtures.each do |fixture|
          model_class.create(fixture)
        end
      end
    end

    # import all seed yaml to table
    #
    # @param seed_dir    [String]
    # @param tables      [Array<String>,String] table names array or comma separated table names. if empty, import all seed yaml. if not empty, import only these tables.
    # @param catalogs    [Array<String>,String] catalogs names array or comma separated catalog names. if empty, import all seed yaml. if not empty, import only these tables in catalogs.
    # @param insert_mode [String] 'bulk' or other string. if empty or 'bulk', using bulk insert. if not empty and not 'bulk', import with ActiveRecord.
    def self.import_all(seed_dir: HeartSeed::Helper.seed_dir, tables: ENV["TABLES"], catalogs: ENV["CATALOGS"], insert_mode: ENV["INSERT_MODE"] || BULK)
      # use tables in catalogs
      target_tables = parse_arg_catalogs(catalogs)
      if target_tables.empty?
        # use tables
        target_tables = parse_string_or_array_arg(tables)
      end

      raise "require TABLES or CATALOGS if production" if HeartSeed::Helper.production? && target_tables.empty?

      ActiveRecord::Migration.verbose = true
      Dir.glob(File.join(seed_dir, "*.yml")) do |file|
        table_name = File.basename(file, '.*')
        next unless target_table?(table_name, target_tables)

        ActiveRecord::Migration.say_with_time("#{file} -> #{table_name}") do
          begin
            model_class = table_name.classify.constantize
            if insert_mode == ACTIVE_RECORD
              insert(source_file: file, model_class: model_class)
            else
              bulk_insert(source_file: file, model_class: model_class)
            end
            ActiveRecord::Migration.say("[INFO] success", true)
          rescue => e
            ActiveRecord::Migration.say("[ERROR] #{e.message}", true)
          end
        end
      end
    end

    # import all seed yaml to table with specified shards
    #
    # @param seed_dir    [String]
    # @param tables      [Array<String>,String] table names array or comma separated table names. if empty, import all seed yaml. if not empty, import only these tables.
    # @param catalogs    [Array<String>,String] catalogs names array or comma separated catalog names. if empty, import all seed yaml. if not empty, import only these tables in catalogs.
    # @param insert_mode [String] 'bulk' or other string. if empty or 'bulk', using bulk insert. if not empty and not 'bulk', import with ActiveRecord.
    # @param shard_names [Array<String>]
    def self.import_all_with_shards(seed_dir: HeartSeed::Helper.seed_dir, tables: ENV["TABLES"], catalogs: ENV["CATALOGS"], insert_mode: ENV["INSERT_MODE"] || BULK, shard_names: [])
      shard_names.each do |shard_name|
        ActiveRecord::Migration.say_with_time("import to shard: #{shard_name}") do
          ActiveRecord::Base.establish_connection(shard_name.to_sym)
          import_all(seed_dir: seed_dir, tables: tables, catalogs: catalogs, insert_mode: insert_mode)
        end
      end
    end

    def self.parse_string_or_array_arg(tables)
      return [] unless tables
      return tables if tables.class == Array

      tables.class == String ? tables.split(",") : []
    end

    def self.parse_arg_catalogs(catalogs)
      array_catalogs = parse_string_or_array_arg(catalogs)
      return [] if array_catalogs.empty?

      tables = []
      array_catalogs.each do |catalog|
        tables += HeartSeed::Helper.catalog_tables(catalog)
      end
      tables.compact
    end

    def self.target_table?(source_table, target_tables)
      return true if target_tables.empty?
      target_tables.include?(source_table)
    end
    private_class_method :target_table?
  end
end
