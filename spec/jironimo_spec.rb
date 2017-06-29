require 'spec_helper'

describe "Jironimo GEM" do

  describe "Instantiating the Test Client and getting information" do

    before "all" do
      @my_Jironimo_client = Jironimo.launch
      @my_Jironimo_project = Jironimo.project('ISC')
    end

    it 'can query meta-info about the JIRA warehouse' do
      Jironimo.site.should == 'http://my-jira.net'
      @my_Jironimo_client.class.to_s.should == 'JIRA::Client'
      @my_Jironimo_client.options[:username].should == User.current.core_id
    end

    it 'can find issue types and their attributes' do
      Jironimo.issue_types(/bug/i).description.should == 'A problem which impairs or prevents the functions of the product.'
      Jironimo.issue_types(/bug/i).name.should == 'Bug'
      Jironimo.issue_types(/bug/i).id.to_numeric.should == 1
      Jironimo.issue_types.keys[0..1].should == ["Requirement", "Bug"]
    end

    it 'can find a project by project key or ID' do
      @my_Jironimo_project.id.should == '11020'
      Jironimo.project(11020).should == @my_Jironimo_project
    end

    it 'can use the client instance to find a project' do
      @my_Jironimo_project.url.should == '/rest/api/2/project/11020'
      @my_Jironimo_project.self.should == 'http://my-jira.net/rest/api/2/project/11020'
      @my_Jironimo_project.id.to_numeric.should == 11020
      @my_Jironimo_project.key.should == 'ISC'
      @my_Jironimo_project.name.should == 'Information Supply Chain'
      @my_Jironimo_project.lead.should == nil # Why don't we fill this out?
      @my_Jironimo_project.issues.class.should == Array
    end

    it 'can set the current project and access its issues' do
      Jironimo.current_project = 'ISC'
      Jironimo.issues.class.should == Hash
      Jironimo.issues.size.should >= 384 # This is an active project so cannot be ==
      Jironimo.issues.keys[0..1].size.should == 2 # Can't test real key values because it is a living project
    end

    it 'can access an individual issue and its attributes' do
      Jironimo.current_project = 'ISC'
      Jironimo.issues['ISC-463'].issuetype.name.should == 'Improvement'
      Jironimo.issues['ISC-463'].issuetype.description.should == 'An improvement or enhancement to an existing feature or task.'
      Jironimo.issues['ISC-463'].summary.should == 'Add in Jira API to Origen'
      Jironimo.issues['ISC-463'].description.should == 'Origen needs a gneral purpose API for communicating with Jira.  This would be required before the ISC origen application can create code to enahance integration with Jira.'
      Jironimo.issues['ISC-463'].assignee.name.should == 'B07507'
      Jironimo.issues['ISC-463'].assignee.emailAddress.should == 'brian.caquelin@freescale.com'
      Jironimo.issues['ISC-463'].status.name.should == 'Open'
    end

    it 'can change the current project and get different values for the same attributes' do
      Jironimo.current_project = 'ISC'
      first_project_description = Jironimo.issues.values.first.description
      Jironimo.current_project = 'APEX'
      second_project_description = Jironimo.issues.values.first.description
      first_project_description.should_not == second_project_description
    end

    it 'can find the current users issues' do
      # Passing in the optional user argument to enable repeatable testing
      # Typical usage would be Jironimo.my_issues
      Jironimo.current_project = 'ISC'
      Jironimo.my_issues(assignee: 'b07507', verbose: true).values.first.assignee.name.should == User.current.core_id.upcase
      Jironimo.current_project = 'APEX'
      Jironimo.my_issues(assignee: 'b07507').empty?.should == true
    end

    it 'can create and delete a new project issue' do
      Jironimo.current_project = 'ISC'
      project_issue_count = Jironimo.issues.size
      new_issue = Jironimo.new_issue(type: 'Bug', summary: 'my summary', description: 'my description', priority: 1, assignee: 'B07507')
      Jironimo.refresh
      new_project_issue_count = Jironimo.issues.size
      new_project_issue_count.should == project_issue_count + 1
      new_issue.class.should == JIRA::Resource::Issue
      new_issue.delete.should == true
      Jironimo.refresh
      current_project_issue_count = Jironimo.issues.size
      current_project_issue_count.should == project_issue_count
    end
  end
end
