# encoding: utf-8
require 'rubygems'
require 'json'
require File.dirname(File.dirname(File.dirname(__FILE__))) + "/constants.rb"
include Constants
require File.dirname(__FILE__) + '/keychain.rb'
require File.dirname(__FILE__) + '/lsof.rb'
require File.dirname(__FILE__) + '/object.rb'
require File.dirname(__FILE__) + '/os.rb'
require File.dirname(__FILE__) + '/mavensmate.rb'
require 'webrick'
include WEBrick

module MavensMate
  module LocalServer
            
      class << self
        
        def start_test
          server = WEBrick::HTTPServer.new(:Port => 7777)
          ['INT', 'TERM'].each { |signal|
             trap(signal) { server.shutdown } 
          }
          
          server.mount('/project', ProjectServlet)
          server.mount('/project/edit', ProjectEditServlet)
          server.mount('/project/existing', ExistingProjectServlet)
          server.mount('/metadata/list', MetadataListServlet) 
          server.mount('/vc', VersionControlServlet) 
          server.mount('/auth', AuthenticationServlet)
          server.mount('/test', ApexUnitTestServlet)
          server.mount('/metadata/index', MetadataIndexServlet)
          server.mount('/deploy', DeployServlet)
          server.mount('/execute', ExecuteApexServlet)
          server.start  
        end

        def start
          stop
          server = WEBrick::HTTPServer.new(
            :Port => 7777,
            :ServerType => WEBrick::Daemon,
            :RequestTimeout => 1800
          )
          
          ['INT', 'TERM'].each { |signal|
             trap(signal) { server.shutdown } 
          }
          
          server.mount('/project', ProjectServlet)
          server.mount('/project/edit', ProjectEditServlet)
          server.mount('/project/existing', ExistingProjectServlet)
          server.mount('/metadata/list', MetadataListServlet) 
          server.mount('/vc', VersionControlServlet) 
          server.mount('/auth', AuthenticationServlet)
          server.mount('/test', ApexUnitTestServlet)
          server.mount('/metadata/index', MetadataIndexServlet)
          server.mount('/deploy', DeployServlet)
          server.mount('/execute', ExecuteApexServlet)
          server.mount('/connections', OrgConnectionServlet)
          server.start  
        end
      
        def stop
          if Lsof.running?(7125)
            Lsof.kill(7125)
          end
          if Lsof.running?(7777)
            Lsof.kill(7777)
          end          
        end

        class ExecuteApexServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_POST(req, resp)
            begin
              ENV["MM_CURRENT_PROJECT_DIRECTORY"] = req.query["mm_current_project_directory"]
              resp['Content-Type'] = 'json'
              resp['Access-Control-Allow-Origin'] = "*"
              options = {
                :level => req.query["level"],
                :category => req.query["category"],
                :body => req.query["body"]
              }
              result = MavensMate.execute_apex(options)
              resp.body = result.to_json
            rescue Exception => e
              result = {
                  :success  => false, 
                  :message  => e.message + e.backtrace.join("\n") 
              }
              resp.body = result.to_json
            end
          end
        end

        class ApexUnitTestServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_POST(req, resp)
            ENV["MM_CURRENT_PROJECT_DIRECTORY"] = req.query["mm_current_project_directory"]
            require SUPPORT + "/environment.rb"
            require File.dirname(File.dirname(File.dirname(__FILE__))) + "/support/tmvc/lib/application_controller.rb"
            resp['Content-Type'] = 'html'
            resp['Access-Control-Allow-Origin'] = "*"
            test_result = {}
            debug_options = {
              :level => req.query["level"],
              :category => req.query["category"]
            }
            api = req.query["api"]
            begin
              result = MavensMate.run_tests(req.query["selected_tests"].split(","), debug_options, api)
              if result[:run_tests_response] || result[:check_deploy_status_response]
                ac = ApplicationController.new
                if RUBY_VERSION =~ /1.9/
                  Encoding.default_external = Encoding::UTF_8
                  Encoding.default_internal = Encoding::UTF_8
                end 
                if api == "apex"
                  html = ac.render_to_string "unit_test/_test_result", :locals => { :result => result }
                else
                  html = ac.render_to_string "unit_test/_test_result_metadata_api", :locals => { :result => result }
                end
                resp.body = html
              else
                result = {
                  :success  => false, 
                  :message  => result.inspect
                }
                resp.body = result.to_json
              end
            rescue Exception => e
              result = {
                  :success  => false, 
                  :message  => e.message + e.backtrace.join("\n") + "<br/>" + result.inspect
              }
              resp.body = result.to_json
            end
          end
        end

        #indexes server metadata to the .org_metadata file in the project config folder
        class MetadataIndexServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_GET(req, resp)            
            begin              
              if RUBY_VERSION =~ /1.9/
                Encoding.default_external = Encoding::UTF_8
                Encoding.default_internal = Encoding::UTF_8
              end
              resp['Content-Type'] = 'html'
              resp['Access-Control-Allow-Origin'] = "*"
              ENV["MM_CURRENT_PROJECT_DIRECTORY"] = req.query["mm_current_project_directory"]
              mode = req.query["mode"] || ""
              do_refresh = req.query["do_refresh"]
              metadata_array = nil
              if do_refresh == "true" or do_refresh == true
                metadata_array = MavensMate.build_index
              else
                metadata_array = eval(File.read("#{ENV['MM_CURRENT_PROJECT_DIRECTORY']}/config/.org_metadata")) #=> comprehensive list of server metadata    
              end
              if mode == "edit"
                require 'rubygems'
                require 'nokogiri'
                project_package = Nokogiri::XML(File.open("#{ENV['MM_CURRENT_PROJECT_DIRECTORY']}/src/package.xml"))
                project_package.remove_namespaces!
                project_package.xpath("//types/name").each do |node|
                  object_definition = MavensMate::FileFactory.get_meta_type_by_name(node.text) || MavensMate::FileFactory.get_child_meta_type_by_name(node.text)  
                  #=> ApexClass
                  is_parent = !object_definition[:parent_xml_name]
                  server_object = metadata_array.detect { |f| f[:key] == node.text }
                  next if server_object.nil? && is_parent
                        
                  if is_parent
                    server_object[:selected] = "selected"
                    server_object[:select_mode] = (node.previous_element.text == "*") ? "all" : "some"
                    MavensMate.select_all(server_object) if server_object[:select_mode] == "all"
                    next if server_object[:selected] == "all"     
                  end
                  
                  if not is_parent
                    #=> CustomField
                    puts "not parent"
                    parent_object_definition = MavensMate::FileFactory.get_meta_type_by_name(object_definition[:parent_xml_name]) #=> CustomObject
                    prev_node = node.previous_element    
                    while prev_node.not.nil? && prev_node.node_name == "members"
                      next if prev_node.text.not.include? "."
                      obj_name = prev_node.text.split(".")[0] #=> Lead
                      obj_attribute = prev_node.text.split(".")[1] #=> Field_Name__c
                       
                      server_object = metadata_array.detect { |f| f[:key] == object_definition[:parent_xml_name] } #=> CustomObject
                      sobject = server_object[:children].detect {|f| f[:title] == obj_name } #=> Lead
                      sobject_metadata = sobject[:children].detect {|f| f[:title] == object_definition[:tag_name] } #=> fields
                      sobject_metadata[:children].each do |item|
                        if item[:title] == obj_attribute
                          item[:selected] = "selected"
                          break
                        end
                      end          
                      prev_node = prev_node.previous_element || nil
                    end
                  end
                  
                  prev_node = node.previous_element    
                  while prev_node.not.nil? && prev_node.node_name == "members"
                    #skip items in folders for now
                    if prev_node.include? "/"
                      prev_node = prev_node.previous_element || nil
                      next
                    end
                    child_object = server_object[:children].detect {|f| f[:key] == prev_node.text }
                    child_object[:selected] = "selected" if child_object.not.nil?
                    MavensMate.select_all(child_object) if object_definition[:child_xml_names]
                    prev_node = prev_node.previous_element || nil
                  end
                  
                  prev_node = node.previous_element    
                  while prev_node.not.nil? && prev_node.node_name == "members"
                    #process only items in folders
                    if prev_node.text.not.include? "/"
                      prev_node = prev_node.previous_element || nil
                      next
                    end
                    child_object = server_object[:children].detect {|f| f[:key] == prev_node.text.split("/")[0]}        
                    begin  
                      child_object[:children].each do |gchild|
                        gchild[:selected] = "selected" if gchild[:key] == prev_node.text
                      end
                    rescue Exception => e
                      #puts e.message + "\n" + e.backtrace.join("\n")
                    end
                    prev_node = prev_node.previous_element || nil
                  end
                end
              end

              ac = ApplicationController.new
              html = ac.render_to_string "deploy/_metadata_tree", :locals => { :metadata_array => metadata_array, :mode => mode }
              resp.body = html
            rescue Exception => e
                resp['Content-Type'] = 'json'
                resp['Access-Control-Allow-Origin'] = "*"
                result = {
                  :success  => false, 
                  :message  => e.message + "\n\n" + e.backtrace.join("\n")
                }
                resp.body = result.to_json
            end
          end    
        end

        class DeployServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_POST(req, resp)    
            begin
              resp['Content-Type'] = 'html'
              resp['Access-Control-Allow-Origin'] = "*"
              response = ''
              ENV["MM_CURRENT_PROJECT_DIRECTORY"] = req.query["mm_current_project_directory"]
              targets = JSON.parse(req.query["targets"].to_s)
              connections = []
              deploy_targets = []
              pconfig = MavensMate.get_project_config
              pconfig['org_connections'].each do |connection| 
                pw = KeyChain::find_internet_password("#{pconfig['project_name']}-mm-#{connection['username']}")
                server_url = connection["environment"] == "production" ? "https://www.salesforce.com" : "https://test.salesforce.com" 
                connections.push({
                  :un => connection["username"], 
                  :pw => pw,
                  :server_url => server_url,
                  :type => connection["environment"]
                })
              end

              targets.each do |t|
                un = t["username"]
                type = t["type"]
                c = connections.detect { |c| c[:un] == un and c[:type] == type }
                deploy_targets.push(c)
              end

              Thread.abort_on_exception = true
              threads = []
              tree = eval(req.query["tree"].to_s)
              is_check_only = req.query["check_only"]

              deploy_targets.each do |t|
                threads << Thread.new {
                  params = {}
                  params[:un]            = t[:un]
                  params[:pw]            = t[:pw]
                  params[:endpoint_type] = t[:type]
                  params[:package]       = tree
                  params[:check_only]    = is_check_only
                  params[:package_type]  = "Custom"
                  deploy_result = MavensMate.deploy_to_server(params)
                  html = nil
                  begin
                    result = MavensMate::Util.parse_deploy_response(deploy_result)
                    ac = ApplicationController.new
                    html = ac.render_to_string "deploy/_deploy_result", :locals => { :result => result, :is_check_only => params[:check_only], :target_username => t[:un] }
                  rescue
                    html = '<div id="error_message" class="alert-message error"><p><strong>Deployment Failed!</strong></p><p>'+deploy_result[:message]+'</p></div> '
                  end
                  response << html
                }
              end
              threads.each { |t|  t.join }
              ac = ApplicationController.new
              html_payload = ac.render_to_string "deploy/_deploy_target_tabs", :locals => { :deploy_result_html => response, :targets => deploy_targets }
              resp.body = html_payload
            rescue Exception => e
              result = '<div id="error_message" class="alert-message error"><p><strong>Deployment Failed!</strong></p><p>'+e.message + e.backtrace.join("\n")+'</p></div> '
              resp.body = result
            end
          end
        end

        class ExistingProjectServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_POST(req, resp)            
            begin
              params = {}
              params[:pn]                 = req.query["pn"]
              params[:un]                 = req.query["un"]
              params[:pw]                 = req.query["pw"]
              params[:server_url]         = req.query["server_url"]
              params[:existing_location]  = req.query["existing_location"] 
              ENV["MM_WORKSPACE"]         = req.query["where"]
              resp['Access-Control-Allow-Origin'] = "*"
              result = MavensMate.new_project_from_existing_directory(params)
              if result[:success] == true
                if OS.mac? then
                  `killAll MavensMate` 
                  # `'/Applications/Sublime Text 2.app/Contents/SharedSupport/bin/subl' --project '#{ENV["MM_WORKSPACE"]}/#{params[:pn]}/#{params[:pn]}.sublime-project'` if result[:success]
                elsif OS.linux? || OS.windows? then
                  %x{subl --project '#{ENV["MM_WORKSPACE"]}/#{params[:pn]}/#{params[:pn]}.sublime-project'}
                end
              else
                resp.body = result.to_json
              end
            rescue Exception => e
              puts e.message
              resp.body = e.message.to_json
            end
          end
        end

        class ProjectServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_POST(req, resp)            
            begin
              params = {}
              params[:action]     = req.query["action"]
              params[:pn]         = req.query["pn"]
              params[:un]         = req.query["un"]
              params[:pw]         = req.query["pw"]
              params[:server_url] = req.query["server_url"]
              params[:vc_un]      = req.query["vc_un"]
              params[:vc_pw]      = req.query["vc_pw"]
              params[:vc_url]     = req.query["vc_url"]
              params[:vc_type]    = req.query["vc_type"]
              params[:vc_alias]   = req.query["vc_alias"]
              params[:vc_branch]  = req.query["vc_branch"]
              params[:package]    = eval(req.query["tree"]) if params[:action] == "new"
              params[:where]      = req.query["where"] 
              ENV["MM_WORKSPACE"] = req.query["where"]
              resp['Access-Control-Allow-Origin'] = "*"
              if params[:action] == "checkout"
                result = MavensMate.checkout_project(params)
              else
                result = MavensMate.new_project(params)
              end           
              if result[:success]
                if OS.mac? then
                  # `killAll MavensMate` 
                  #`~/bin/subl --project '#{ENV["MM_WORKSPACE"]}/#{params[:pn]}/.sublime-project'` if result[:success]
                  `'/Applications/Sublime Text 2.app/Contents/SharedSupport/bin/subl' --project '#{ENV["MM_WORKSPACE"]}/#{params[:pn]}/#{params[:pn]}.sublime-project'` if result[:success]
                elsif OS.linux? || OS.windows? then
                  %x{subl --project '#{ENV["MM_WORKSPACE"]}/#{params[:pn]}/#{params[:pn]}.sublime-project'}
                end
              else
                resp.body = result.to_json
              end
            rescue Exception => e
              puts e.message
              resp.body = e.message.to_json
            end
          end
        end

        class OrgConnectionServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_POST(req, resp)  
            begin
              un = req.query["un"].to_s
              pw = req.query["pw"].to_s
              server_url = req.query["server_url"].to_s
              client = MavensMate::Client.new({ 
                :username => req.query["un"], 
                :password => req.query["pw"], 
                :endpoint => req.query["server_url"], 
                :override_session => true
              })
              project_directory = req.query["pd"].to_s
              ENV['MM_CURRENT_PROJECT_DIRECTORY'] = project_directory
              environment = MavensMate::Util.get_endpoint_type_by_short_url(server_url)
              require 'yaml'
              yml = YAML::load(File.open("#{project_directory}/config/settings.yaml")) 
              project_name = yml['project_name']      
              connections = []
              if yml["org_connections"]
                connections = yml["org_connections"]
                keychain_name = project_name + "-mm-"
                KeyChain::add_generic_password("#{project_name}-mm-#{un}", "#{project_name}-mm-#{un}", pw)
                connections.push({ "username" => un, "environment" => environment })
              else
                KeyChain::add_generic_password("#{project_name}-mm-#{un}", "#{project_name}-mm-#{un}", pw)
                yml["org_connections"] = [{ "username" => un, "environment" => environment }]
                connections.push({ "username" => un, "environment" => environment })
              end 
              File.open("#{project_directory}/config/settings.yaml", 'w') { |f| YAML.dump(yml, f) }
              resp['Content-Type'] = 'json'
              resp['Access-Control-Allow-Origin'] = "*"
              ac = ApplicationController.new
              connections = MavensMate.get_org_connections 
              html = ac.render_to_string "org_connection/_connections", :locals => { :connections => connections }
              result = {
                :success  => true,
                :message => html
              }
              resp.body = result.to_json
            rescue Exception => e
              html = '<div id="error_message" class="alert-message error"><p><strong>Error!</strong></p><p>'+e.message+'</p></div> '
              result = {
                :success  => false,
                :message => html
              }
              resp.body = result.to_json
            end
          end

          def do_DELETE(req, resp) 
            begin
              un = req.query["un"].to_s
              require 'yaml'
              project_directory = req.query["pd"].to_s
              ENV['MM_CURRENT_PROJECT_DIRECTORY'] = project_directory
              yml = YAML::load(File.open("#{project_directory}/config/settings.yaml")) 
              project_name = yml['project_name']      
              conns = nil
              if yml["org_connections"]
                conns = yml["org_connections"]
                conns.delete_if{|conn| conn["username"] == un }
                yml["org_connections"] = conns
              end
              File.open("#{project_directory}/config/settings.yaml", 'w') { |f| YAML.dump(yml, f) } 
              resp['Content-Type'] = 'json'
              resp['Access-Control-Allow-Origin'] = "*"
              ac = ApplicationController.new
              connections = MavensMate.get_org_connections 
              html = ac.render_to_string "org_connection/_connections", :locals => { :connections => connections }
              result = {
                :success  => true,
                :message => html
              }
              resp.body = result.to_json
            rescue Exception => e
              html = '<div id="error_message" class="alert-message error"><p><strong>Error!</strong></p><p>'+e.message+'</p></div> '
              result = {
                :success  => false,
                :message => html
              }
              resp.body = result.to_json 
            end
          end
        end

        class ProjectEditServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_POST(req, resp)            
            begin
              tree = eval(req.query["tree"])  
              result = MavensMate.clean_project({ :update_sobjects => false, :update_package => true, :package => tree, :force_return => true })
              if result[:success] == true
                if OS.mac? then
                  `killAll MavensMate`
                end
              end
              resp['Access-Control-Allow-Origin'] = "*"
              resp.body = result.to_json
            rescue Exception => e
              puts e.message + e.backtrace.join("\n")
              resp.body = e.message.to_json + e.backtrace.join("\n")
            end        
          end
        end

        class MetadataNewServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_POST(req, resp)            
            begin              
              result = MavensMate.new_metadata({
                :meta_type        => req.query["meta_type"], 
                :api_name         => req.query["api_name"], 
                :object_api_name  => req.query["object_api_name"],
                :apex_class_type  => req.query["apex_class_type"]
              }) 
              resp['Access-Control-Allow-Origin'] = "*"
              puts result.inspect
              `killAll MavensMate` if result[:success] #=> result[:message] 
              #`~/bin/subl --command '#{ENV["MM_CURRENT_PROJECT_DIRECTORY"]}/#{params[:pn]}/.sublime-project'` if result[:success]
              `/Applications/Sublime\ Text\ 2.app/Contents/SharedSupport/bin/subl --command '#{ENV["MM_CURRENT_PROJECT_DIRECTORY"]}/#{params[:pn]}/#{params[:pn]}.sublime-project'` if result[:success]
              #windows it's sublime_text --command
            rescue Exception => e
              puts e.message
            end
          end    
        end

        class AuthenticationServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_GET(req, resp)            
            begin              
              update_creds = req.query["update_creds"] || false
              sid = nil
              murl = nil
              client = MavensMate::Client.new({ 
                :username => req.query["un"], 
                :password => req.query["pw"], 
                :endpoint => req.query["server_url"], 
                :override_session => req.query["override_session"] || false
              })
              resp['Access-Control-Allow-Origin'] = "*"
              if ! client.sid.nil? && ! client.metadata_server_url.nil?
                if update_creds
                  if RUBY_VERSION =~ /1.9/
                    Encoding.default_external = Encoding::UTF_8
                    Encoding.default_internal = Encoding::UTF_8
                  end
                  ENV['MM_CURRENT_PROJECT_DIRECTORY'] = req.query["pd"].to_s
                  un = req.query["un"].to_s
                  pw = req.query["pw"].to_s
                  server_url = req.query["server_url"].to_s
                  environment = (server_url.include? "test") ? "sandbox" : "production"
                  require 'yaml'
                  yml = YAML::load(File.open("#{ENV['MM_CURRENT_PROJECT_DIRECTORY']}/config/settings.yaml")) 
                  project_name = yml['project_name'].to_s
                  yml['username'] = un
                  yml['environment'] = environment 
                  File.open("#{ENV['MM_CURRENT_PROJECT_DIRECTORY']}/config/settings.yaml", 'w') { |f| YAML.dump(yml, f) }
                  MavensMate.add_to_keychain(project_name, pw)
                  FileUtils.rm_r("#{ENV['MM_CURRENT_PROJECT_DIRECTORY']}/config/.session") if File.exist?("#{ENV['MM_CURRENT_PROJECT_DIRECTORY']}/config/.session")
                  result = {
                    :success  => true,
                    :message => "Credentials successfully updated!"
                  }
                  resp.body = result.to_json
                else
                  result = {
                    :success  => true, 
                    :sid      => client.sid, 
                    :murl     => client.metadata_server_url 
                  }
                  resp.body = result.to_json
                end
              end
            rescue Exception => e
                result = {
                  :success  => false, 
                  :message  => e.message 
                }
                resp.body = result.to_json
            end
          end    
        end

        class MetadataListServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_GET(req, resp)            
            begin              
              sid       = req.query["sid"]
              meta_type = req.query["key"]
              murl      = req.query["murl"]
              murl      = URI.unescape(murl)
              client = MavensMate::Client.new({ 
                :sid => sid, 
                :metadata_server_url => murl 
              })
              result = client.list(meta_type, false)
              resp['Access-Control-Allow-Origin'] = "*"
              resp.body = result 
            rescue Exception => e
                result = {
                  :success => false, 
                  :message => e.message 
                }
                resp.body = result
            end
          end    
        end
        
        class VersionControlServlet < WEBrick::HTTPServlet::AbstractServlet
          def do_GET(req, resp)            
            begin              
              svn_un  = req.query["svn_un"]
              svn_pw  = req.query["svn_pw"]
              vc_type = req.query["vc_type"].downcase!
              vc_url  = req.query["vc_url"]
              resp['Access-Control-Allow-Origin'] = "*"
              
              require 'rubygems'
              require 'nokogiri'
              opts = []
              if vc_type == "svn"
                response = %x{svn list --xml --trust-server-cert --non-interactive --username #{svn_un} --password #{svn_pw} '#{vc_url}'}                    
                doc = Nokogiri::XML(response)
                doc.remove_namespaces!
                doc.xpath("//entry/name").each do |node|
                  opts.push({:url => vc_url+"/"+node.text, :title => node.text})
                end 
              elsif vc_type == "git"
                response = %x{git ls-remote '#{vc_url}'} 
                response.split("\n").each do |branch|
                  branch_name = branch.split("\t")[1]
                  opts.push({ :url => branch_name, :title => branch_name })
                end 
              end
              resp.body = opts.to_json
            rescue Exception => e
              puts e.message
            end
          end    
        end
        
      end
        
  end 
end