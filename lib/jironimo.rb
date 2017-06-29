require 'origen'
require_relative '../config/application.rb'
require 'jira-ruby'

module Jironimo
  # Hash of all projects
  attr_accessor :projects

  # Current project selected
  attr_accessor :current_project

  # JIRA client instance
  attr_accessor :client

  # JIRA site
  attr_accessor :site

  # All issues types found in the client instance
  attr_accessor :issue_types

  # Issues for the currently selected project
  attr_accessor :issues

  IssuesTableRow = Struct.new(:key, :assignee, :status, :summary)

  MAX_ISSUES = 100_000

  # Issue status types that can be passed as an argument
  STATUS_TYPES = ['Open', 'In Progress', 'Resolved', 'All', 'All Open']

  # JQL events
  EVENT_TYPES = %w(created resolved updated)

  def self.initialize
    @client ||= nil
    @site ||= nil
    @projects ||= {}
    @issue_types ||= {}
    @current_project ||= nil
    @issues ||= {}
  end

  # JIRA sites
  def self.site
    @site
  end

  # JIRA client
  def self.client
    @client
  end

  # Allows filtering of @issue_types
  def self.issue_types(filter_arg = nil)
    if filter_arg.nil?
      return @issue_types
    else
      issue_types_found = @issue_types.filter(filter_arg)
      if issue_types_found.size == 1
        return issue_types_found.values.first
      elsif issue_types_found.size > 1
        Origen.log.warn "Found more than one JIRA issue type using the argument '#{filter_arg}', refine your search from #{issue_types_found.keys.join(', ')}"
        return issue_types_found.values
      else
        Origen.log.warn "Found no JIRA issue types using the argument '#{filter_arg}', refine your search from #{issue_types_found.keys.join(', ')}"
        return nil
      end
    end
  end

  # Allows filtering of @projects
  def self.projects(filter_arg = nil)
    if filter_arg.nil?
      return @projects
    else
      projects_found = @projects.filter(filter_arg)
      if projects_found.size == 1
        return projects_found.values.first
      elsif projects_found > 1
        Origen.log.warn "Found more than one JIRA project using the argument '#{filter_arg}', refine your search from #{projects_found.keys.join(', ')}"
        return projects_found.values
      else
        Origen.log.warn "Found no JIRA issue types using the argument '#{filter_arg}', refine your search from #{projects_found.keys.join(', ')}"
        return nil
      end
    end
  end

  # Retrieve a project using a numeric ID or String key
  def self.project(id)
    # Try the project key first and then the ID
    if id.is_a? String
      return projects(id)
    elsif id.is_a? Integer
      # Try the ID
      projects_found = @projects.select { |key, p| p.id.to_numeric == id }
      if projects_found.size == 1
        return projects_found.values.first
      else
        Origen.log.warn "Found more than one JIRA project using the argument '#{id}', refine your search from #{projects_found.keys.join(', ')}"
        return projects_found.values
      end
    end
  end

  # Re-fresh the JIRA client and releated module accessors
  # Useful after adding, deleting, ormodifying anythign on the JIRA server
  def self.refresh(options = {})
    query_options = {
      fields:      [],
      start_at:    0,
      max_results: MAX_ISSUES
    }.update(options)
    Origen.log.errpr 'Jironimo#refresh needs Jironimo.current_project to be set' if @current_project.nil?
    Origen.log.error 'Jironimo#refresh needs to have Jironimo.client to be valid' if @client.nil?
    @projects = create_projects_hash(@client.Project.all)
    @issue_types = create_issue_types_hash(@client.Issuetype.all)
    @issues = {}
    @client.Issue.jql("project = #{@current_project.key}", query_options).each do |issue|
      @issues[issue.key] = issue
    end
  end

  # Set the current project, enables project specific accessors like @issues
  def self.current_project=(id, options = {})
    query_options = {
      fields:      [],
      start_at:    0,
      max_results: MAX_ISSUES
    }.update(options)
    project_search = project(id)
    if project_search.is_a? JIRA::Resource::Project
      @current_project = project_search
      # Find all of the issues for this project
      @issues = {} unless @issues.empty?
      @client.Issue.jql("project = #{id}", query_options).each do |issue|
        @issues[issue.key] = issue
      end
      # This code only returns 50 results max
      # @current_project.issues.each do |issue|
      #  @issues[issue.key] = issue
      # end
    else
      @current_project = nil
    end
  end

  # Returns the curren project instance
  def self.current_project
    @current_project
  end

  # Returns a hash of JIRA issues assigned to the current user
  # Defaults to 'Open' or 'In Progress' issue status
  def self.my_issues(options = {})
    query_options = {
      verbose:     false,
      assignee:    User.current.core_id.upcase, # Just there to enable rspec testing
      project:     nil,
      fields:      [],
      start_at:    0,
      max_results: MAX_ISSUES,
      status:      'All Open'
    }.update(options)
    my_issues = {}
    console_print = query_options.delete(:verbose)
    Origen.log.error 'User option must be a String, exiting...' unless query_options[:assignee].is_a? String
    assignee = query_options.delete(:assignee)
    jql_str = "assignee = #{assignee.upcase}"
    if options[:project].nil?
      # No argument passed so check if @current_project is set
      jql_str += " AND project = #{@current_project.key}" unless @current_project.nil?
    else
      jql_str += " AND project = #{query_options[:project]}"
    end
    # Check which issue status types to retrieve
    if STATUS_TYPES.include? query_options[:status]
      # Status type is valid, need to see if it is a special one that involves multiple JIRA status types (e.g. 'All Open')
      begin
        case query_options[:status]
        when 'All Open'
          jql_str += " AND status in (Open, 'In Progress')"
        when 'All'
          jql_str = jql_str # Don't change naything as status doesn't need to be filtered
        else
          jql_str += " AND status = #{query_options[:status]}"
        end
      ensure
        query_options.delete(:status)
      end
    else
      Origen.log.error "status option is not valid, choose from #{STATUS_TYPES.join(', ')}, exiting..."
    end
    if @client.nil?
      Origen.log.error 'No JIRA client instantiated, cannot check for your issues, exiting...'
    else
      @client.Issue.jql(jql_str, query_options).each do |issue|
        my_issues[issue.key] = issue
      end
    end
    show_issues(my_issues) if console_print
    my_issues
  end

  # Get the latest issues
  def self.latest_issues(time, options = {})
    query_options = {
      verbose:     false,
      assignee:    User.current.core_id.upcase, # Just there to enable rspec testing
      fields:      [],
      start_at:    0,
      max_results: MAX_ISSUES,
      event:       'created'
    }.update(options)
    latest_issues = {}
    console_print = query_options.delete(:verbose)
    event = query_options.delete(:event)
    assignee = query_options.delete(:assignee)
    Origen.log.errpr 'Jironimo.current_project is not set, exiting...' if @current_project.nil?
    Origen.log.error 'Jironimo.client is not set, exiting...' if @client.nil?
    Origen.log.error "Event '#{event}' is not supported, choose from #{EVENT_TYPES.join(', ')}, exiting..." unless EVENT_TYPES.include? event
    Origen.log.error "Could not get latest issues with argument '#{time}', exiting..." unless jql_time_ok?(time)
    jql = "assignee = #{assignee} AND #{event} <= '#{time}'"
    @client.Issue.jql(jql).each do |issue|
      latest_issues[issue.key] = issue
    end
    latest_issues
  end
  # alias_method self(:latest, :latest_issues

  # Allows filtering of @issues
  def self.issues(options = {})
    options = {
      verbose: false
    }.update(options)
    if @current_project.nil?
      return {}
    elsif @current_project.is_a? JIRA::Resource::Project
      show_issues(@issues) if options[:verbose]
      return @issues
    else
      Origen.log.error "Jironimo.current_project is of incorrect type '#{@current_project.class}', should be nil or JIRA::Resource::Project, exiting.."
    end
  end

  # Launches the JIRA interface client and initializes
  # @projects and @issue_types
  def self.launch(options = {})
    options = {
      username:     User.current.id,
      password:     'my_password',
      site:         'http://my-jira.net',
      auth_type:    :basic,
      use_ssl:      false,
      context_path: ''
    }.update(options)
    initialize
    @client = JIRA::Client.new(options)
    @site = options[:site]
    @projects = create_projects_hash(@client.Project.all)
    @issue_types = create_issue_types_hash(@client.Issuetype.all)
    @client
  end

  # Returns a hash of issue types with issue type name as key and
  # issue type number as value
  def self.issue_type_mapping
    issue_type_names = {}
    @issue_types.each do |type_name, issue_type|
      issue_type_names[type_name] = issue_type.id
    end
    issue_type_names
  end

  def self.update_issue(issue_key)
    options = {
      type:           nil,
      summary:        nil,
      description:    nil,
      assignee:       nil,
      priority:       nil,
      components:     nil,
      comment:        nil,
      affectsVersion: nil,
      timespent:      nil,
      resolution:     nil
    }.update(options)
    Origen.log.error "Cannot update issue '#{issue_key}', please set the current project" if @issues.empty?
    project_attr = 'key'
    args_result, options = check_issue_args(options)
    Origen.log.error "Updating JIRA issue '#{issue_key}' failed due to bad arguments, check previous log warnings, exiting..." unless args_result
    issue = @issues[issue_key]
    issue.save(assemble_issue_fields(options, project_attr))
    issue
  end

  # Create anew JIRA issue for the current project or one passed as an argument
  def self.new_issue(options = {})
    options = {
      project:     nil,
      type:        nil,
      summary:     nil,
      description: nil,
      assignee:    User.current.core_id.upcase, # core ID uppercase
      priority:    3,
      components:  'Origen'
      # affected_version: nil TODO: Add support for setting affected version attribute for issue creation
    }.update(options)
    project_attr = ''
    args_result, options = check_issue_args(options)
    Origen.log.error 'Creating a new JIRA issue failed due to bad arguments, check previous log warnings, exiting...' unless args_result
    if options[:project].numeric?
      project_attr = 'id'
    elsif options[:project].is_a? String
      project_attr = 'key'
    else
      Origen.log.error 'options[:project] must be String (use project key) or Integer (use project ID), exiting...'
    end
    issue = @client.Issue.build
    issue.save(assemble_issue_fields(options, project_attr))
    issue
  end

  # Delete a JIRA issue
  def self.delete_issue(issue_key)
    Origen.log.error "Could not delete issue '#{issue_key}', exiting..." unless @issues.include? issue_key
    @issues[issue_key].delete
  end

  private

  def self.jql_time_ok?(time)
    result = true
    time.split(/\s+/).each do |time_arg|
      if time_arg[/^[-|+]?\d+[d|h|m|w|y]$/].nil?
        Origen.log.warn "Could not parse jql time argument #{time_arg}"
        result = false
      end
    end
    result
  end

  def self.assemble_issue_fields(options, project_attr)
    issues_hash = Hash.new do |h, k|
      h[k] = {}
    end
    options.each do |attr, value|
      case attr
      when :summary, :description
        issues_hash['fields'][attr.to_s] = value unless value.nil?
      when :project
        issues_hash['fields'][attr.to_s] = Hash[project_attr.to_s, value] unless value.nil?
      when :type
        issues_hash['fields']['issuetype'] = Hash['name', value] unless value.nil?
      when :assignee
        issues_hash['fields'][attr.to_s] = Hash['name', value] unless value.nil?
      when :priority
        issues_hash['fields'][attr.to_s] = Hash['id', value.to_s] unless value.nil?
      when :components
        value = [value] unless value.is_a? Array
        component_array = []
        value.each do |component|
          component_key = ''
          if component.is_a? String
            if component.numeric?
              component_key = 'id'
            else
              component_key = 'name'
            end
          elsif component.is_a? Integer
            component_key = 'id'
          else
            Origen.log.error "Component option '#{component}' is not the correct type, choose from String or Integer, exiting..."
          end
          component_array << Hash[component_key, component.to_s]
        end
        issues_hash['fields'][attr.to_s] = component_array
      else
        Origen.log.warn "JIRA issue option '#{attr}' is not recognized"
      end
    end
    issues_hash
  end

  def self.check_issue_args(options)
    result = true
    if options[:project].nil?
      if @current_project.nil?
        Origen.log.warn 'options[:project] must be supplied or a current project be set with Jironimo#current_product='
        result = false
      else
        options[:project] = @current_project.id
      end
    elsif options[:project].is_a?(Numeric)
      # Convert the number to a String as jira requires a String argument
      options[:project] = options[:project].to_s
    end
    string_options = options.reject { |k, v| [:project, :priority].include? k }
    string_options.each do |_key, value|
      unless value.is_a? String
        Origen.log.warn "JIRA issue creation argument '#{value}' must be a String"
        result = false
      end
    end
    unless @issue_types.include?(options[:type])
      Origen.log.warn "JIRA issue type argument '#{options[:type]}' is not valid, choose from:\n#{@issue_types.keys.sort.join("\n")}"
      result = false
    end
    [result, options]
  end

  def self.show_issues(issues)
    whitespace_padding, table_issues, column_widths, header, project_header, table = 3, [], {}, '', '', []
    # Create a hash with key being the issue key and the value being the issue summary
    issues.each do |key, issue|
      assignee = ''
      issue.assignee.nil? ? assignee = '' : assignee = issue.assignee.name
      table_issues << IssuesTableRow.new(key, assignee, issue.status.name, issue.summary)
    end
    %w(Key Assignee Status Summary).each do |column|
      sym = column.downcase.to_sym
      if column.length > table_issues.map(&sym).max_by(&:length).length
        column_widths[column] = column.length + whitespace_padding
      else
        column_widths[column] = table_issues.map(&sym).max_by(&:length).length + whitespace_padding
      end
    end
    column_widths.each do |attr_name, column_width|
      header += "| #{attr_name}".ljust(column_width)
    end
    project_header += "| #{@current_project.key}: #{@current_project.name}".ljust(header.length)
    header += '|'
    table << '-' * header.length
    table << project_header += '|'
    table << '=' * header.length
    table << header
    table << '=' * header.length
    table_issues.each do |issue|
      row = ''
      row = "| #{issue.key}".ljust(column_widths['Key']) + "| #{issue.assignee}".ljust(column_widths['Assignee']) + "| #{issue.status}".ljust(column_widths['Status']) + "| #{issue.summary}".ljust(column_widths['Summary']) + '|'
      table << row
    end
    table << '-' * header.length
    puts table.flatten.join("\n")
  end

  def self.create_issue_types_hash(arr)
    issue_types_hash = {}
    arr.each do |issue_type|
      issue_types_hash[issue_type.name] = issue_type
    end
    issue_types_hash
  end

  def self.create_projects_hash(arr)
    project_hash = {}
    arr.each do |project|
      project_hash[project.key] = project
    end
    project_hash
  end
end
