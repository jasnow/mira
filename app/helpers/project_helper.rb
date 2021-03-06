module ProjectHelper

  def datapackage_errors
    @datapackage_errors = {
      already_uploaded: "A datapackage already exists for this project.",
      no_upload: "You must upload a datapackage.json file.",
      bad_json: "Failed to parse datapackage.json.",
      resources_missing: "datapackage.json must contain a 'resources' array.",
      resources_not_array: "datapackage.json must contain a 'resources' array.",
      resources_empty: "datapackage.json must contain a non-empty 'resources' array.",
      missing_path: "Each resource must have a path.",
      missing_schema: "Each resource must have a schema.",
      path_not_string: "Resource path must be a String, e.g. 'mydata.csv'",
      path_empty: "Resource 'path' is empty.",
      path_not_csv: "Resource 'path' should refer to a csv file.",
      schema_not_hash: "Resource 'schema' must be a Hash.",
      schema_no_fields: "Resource 'schema' must contain 'fields'.",
      schema_not_array: "Resource schema 'fields' must be an Array.",
      field_not_name_and_type: "Each resource schema field must contain 'name' and 'type' keys.",
      field_invalid_name: "Field name is not valid.",
      field_invalid_type: "Field type is not valid.",
      delimiter_too_long: "Delimiter character must be a single character.",
      quote_char_too_long: "Quote character must be a single character."
    }
  end

  def datasource_errors
    @datasource_errors = {
      no_upload: "You must upload one or more csv files.",
      no_datapackage: "This project has no associated datapackage.",
      missing_resource_metadata: "This project's datapackage has no resource metadata.",
      non_csv: "Only csv files can be uploaded.",
      already_uploaded: "A file of this name has been uploaded already",
      no_resource_metadata: "This project's datapackage has no metadata for uploaded file.",
      field_missing_metadata: "This project's datapackage has metadata for the uploaded file but none for its fields."
    }
  end

  def add_path_to_feedback(resource)
    @feedback[:errors] << "Path: " + resource["path"].to_s + "."
  end

  def add_field_to_feedback(field)
    @feedback[:errors] << "Field: " + field.to_s + "."
  end

  def check_and_clean_datapackage(dp)
    dp_path = dp.tempfile.path
    dp_file = File.read(dp_path)
    json_dp = {}
    begin
      json_dp = JSON.parse(dp_file)
    rescue => e
      @feedback[:errors] << datapackage_errors[:bad_json]
    else
      @feedback[:errors] << datapackage_errors[:resources_missing] if !json_dp.has_key? "resources"
      @feedback[:errors] << datapackage_errors[:resources_not_array] if (json_dp.has_key? "resources") && (json_dp["resources"].class != Array)
      @feedback[:errors] << datapackage_errors[:resources_empty] if (json_dp.has_key? "resources") && (json_dp["resources"].empty?)
    end

    json_dp = trim_datapackage(json_dp)

    if @feedback[:errors].empty?
      json_dp["resources"].each do |resource|
        @feedback[:errors] << datapackage_errors[:missing_path] if !resource.has_key? "path"
        @feedback[:errors] << datapackage_errors[:missing_schema] if !resource.has_key? "schema"
        if resource.has_key? "path"
          extension = (resource["path"].to_s.split("/").last.to_s.split(".").length > 1) ? resource["path"].to_s.split("/").last.to_s.split(".").last.downcase : ""
          if resource["path"].class != String
            @feedback[:errors] << datapackage_errors[:path_not_string]
            add_path_to_feedback resource
          elsif [nil, ""].include? resource["path"]
            @feedback[:errors] << datapackage_errors[:path_empty]
            add_path_to_feedback resource
          elsif extension != "csv"
            @feedback[:errors] << datapackage_errors[:path_not_csv]
            add_path_to_feedback resource
          end
        end

        if resource.has_key? "path" and resource.has_key? "schema"
          if resource["schema"].class != Hash
            @feedback[:errors] << datapackage_errors[:schema_not_hash]
            add_path_to_feedback resource
          elsif !resource["schema"].has_key? "fields"
            @feedback[:errors] << datapackage_errors[:schema_no_fields]
            add_path_to_feedback resource
          elsif resource["schema"]["fields"].class != Array
            @feedback[:errors] << datapackage_errors[:schema_not_array]
            add_path_to_feedback resource
          else
            resource["schema"]["fields"].each do |field|
              if not (field.has_key? "name" and field.has_key? "type")
                @feedback[:errors] << datapackage_errors[:field_not_name_and_type]
                add_path_to_feedback resource
                add_field_to_feedback field
              else
                if (field["name"] =~ /^[a-zA-Z_][a-zA-Z0-9_]*$/) == nil
                  @feedback[:errors] << datapackage_errors[:field_invalid_name]
                  add_path_to_feedback resource
                  add_field_to_feedback field
                end
                unless DATAPACKAGE_TYPE_MAP.keys.include? field["type"].downcase
                  @feedback[:errors] << datapackage_errors[:field_invalid_type]
                  add_path_to_feedback resource
                  add_field_to_feedback field
                  @feedback[:errors] << "Valid types are " + DATAPACKAGE_TYPE_MAP.keys.join(", ") + "."
                end
              end
            end
          end
        end
      end
    end
    json_dp
  end


  def extract_and_save_datapackage_resources(dp_object,json_dp)
    json_dp["resources"].each do |res|
      dp_res = DatapackageResource.new(datapackage_id: dp_object.id, path: res["path"], table_ref: File.basename(res["path"],".*"))
      dp_res.format = res["format"] if res.has_key? "format"
      dp_res.mediatype = res["mediatype"] if res.has_key? "mediatype"
      # delimiter
      delimiter = ','
      if res.has_key? "dialect" and res["dialect"].has_key? "delimiter"
        dlm_len = res["dialect"]["delimiter"].length
        if dlm_len > 1
          @feedback[:errors] << datapackage_errors[:delimiter_too_long]
        elsif dlm_len != 0
          delimiter = res["dialect"]["delimiter"]
        end
      else
        @feedback[:notes] << "datapackage.json does not specify a delimiter character so it defaults to a comma."
      end
      dp_res.delimiter = delimiter
      # quote character
      qchar = '"'
      if res.has_key? "dialect" and res["dialect"].has_key? "quote"
        qchar_len = res["dialect"]["quote"].length
        if qchar_len > 1
          @feedback[:errors] << datapackage_errors[:quote_char_too_long]
        elsif qchar_len != 0
          qchar = res["dialect"]["quote"]
        end
      else
        @feedback[:notes] << "datapackage.json does not specify a quote character so it defaults to a double quote."
      end
      dp_res.quote_character = qchar

      if dp_res.valid? && @feedback[:errors].empty?
        dp_res.save
        extract_and_save_resource_fields(json_dp,dp_res)
      else
        @feedback[:errors] << "Datapackage resource not saved for " + res["path"] + ". ERRORS: " + dp_res.to_a.join(", ") + "."
      end
    end
  end


  def extract_and_save_resource_fields(json_dp,resource)
    feedback = { errors: [], warnings: [], notes: []}
    resource_schema = json_dp["resources"].find{ |r| r["path"] == resource.path }["schema"]
    resource_schema["fields"].each_with_index do |field,ndx|
      res_field = DatapackageResourceField.new(datapackage_resource_id: resource.id, name: field["name"], ftype: field["type"], order: ndx + 1)
      if field["constraints"].present?
        field_min = custom_is_string_int?(field["constraints"]["minimum"]) ? field["constraints"]["minimum"].to_i : 0
        field_max = custom_is_string_int?(field["constraints"]["maximum"]) ? field["constraints"]["maximum"].to_i : 0
        res_field.big_integer = true if [field_min.abs, field_max.abs].max > 2147483647 # 2^31-1
      end
      res_field.save
    end
  end


  def check_datasources
    if @datapackage.nil?
      @feedback[:errors] << datasource_errors[:no_datapackage]
    elsif @csv_uploads.nil? || @csv_uploads.empty?
      @feedback[:errors] << datasource_errors[:no_upload]
    elsif @datapackage.datapackage_resources.nil?
      @feedback[:errors] << datasource_errors[:missing_resource_metadata]
    else
      datasource_filenames = @csv_uploads.map { |u| u.original_filename }
      datapackage_filenames = @datapackage.datapackage_resources.map { |ds| ds.path }
      existing_uploads = @project.datasources.map { |ds| ds.datafile_file_name }
      @csv_uploads.each do |csv|
        if csv.original_filename !~ /\.csv/i
          @feedback[:errors] << datasource_errors[:non_csv]
          @feedback[:errors] << "Upload: " + csv.original_filename + "."
        elsif datapackage_filenames.exclude? csv.original_filename
          @feedback[:errors] << datasource_errors[:no_resource_metadata]
          @feedback[:errors] << "Upload: " + csv.original_filename + "."
        elsif existing_uploads.include? csv.original_filename
          @feedback[:errors] << datasource_errors[:already_uploaded]
          @feedback[:errors] << "Upload: " + csv.original_filename + "."
        else
          dp_res = @datapackage.datapackage_resources.where(path: csv.original_filename).first
          dp_res_fields = dp_res.datapackage_resource_fields
          if dp_res_fields.empty?
            # shouldn't ever reach here...but just in case
            @feedback[:errors] << datasource_errors[:field_missing_metadata]
            @feedback[:errors] << "Upload: " + csv.original_filename
          else
            # At this point we know we have metadata for all uploaded files (via
            # the processing of the uploaded datapackage.json file).
            # Do a quick check of each csv file.
            dp_res_fields = dp_res.datapackage_resource_fields
            csv_actual_fields = CSV.open(csv.tempfile, 'r') { |csvfile| csvfile.first }.sort
            csv_metadata_fields = dp_res_fields.map { |f| f.name }.sort
            if csv_actual_fields != csv_metadata_fields
              @feedback[:errors] << "The datapackage.json field names for " + csv.original_filename +
                                    " do not match the fields in the csv file. Expected: [" +
                                    csv_metadata_fields.join(", ") + "]. Actual: [" + csv_actual_fields.join(", ") + "]."
            end
          end
        end
      end
    end
  end


  def save_datapackage(dp)
    dp.save # save first...then can get public url
    dp.public_url = dp.datapackage.url.partition("?").first
    dp.save
  end


  def trim_datapackage(json_dp)
    # remove all datapackage.json keys which are not needed (e.g. README). Doing this here
    # because embedded html spooks the server. It detects content-spoofing and getting the
    # error "Datapackage has contents that are not what they are reported to be"
    json_dp.each do |k,v|
      if !["name","title","description","resources"].include? k
        @feedback[:notes] << "Trimming '" + k + "' attribute from datapackage.json"
        json_dp.delete(k)
      end
    end
    json_dp
  end


  def save_datasource(csv)
    csv_file = File.open(csv.tempfile.path)
    ds = @project.datasources.create(datafile: csv_file, datafile_file_name: csv.original_filename, datapackage_id: @datapackage.id) # ds = datasource
    if ds.valid?
      set_datasource_table_name(ds)
      ds.public_url = ds.datafile.url.partition("?").first
    else
      @feedback[:errors] << "Failed to create datasource. Errors: " + ds.errors.to_a.join(", ")
    end
    retval = ds.save ? ds : nil
    retval
  end


  def set_datasource_table_name(ds)
    ds.db_table_name = Rails.configuration.x.db_table_prefix.downcase + ds.project_id.to_s + "_" + ds.id.to_s
  end


end
