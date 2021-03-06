require 'spec_helper'

CLOUD_APPLICATION_CONTEXT_INITIALIZER = 'org.cloudfoundry.reconfiguration.spring.CloudApplicationContextInitializer'
CLOUD_APP_ANNOTATION_CONFIG_CLASS = 'org.cloudfoundry.reconfiguration.spring.web.CloudAppAnnotationConfigAutoReconfig'

describe "A Spring application being staged" do
  before do
    app_fixture :spring_guestbook
  end

  it "is packaged with a startup script" do
    stage :spring do |staged_dir|
      executable = '%VCAP_LOCAL_RUNTIME%'
      start_script = File.join(staged_dir, 'startup')
      start_script.should be_executable_file
      webapp_root = staged_dir.join('tomcat', 'webapps', 'ROOT')
      webapp_root.should be_directory
      webapp_root.join('WEB-INF', 'web.xml').should be_readable
      script_body = File.read(start_script)
      script_body.should == <<-EXPECTED
#!/bin/bash
export CATALINA_OPTS="-Xms512m -Xmx512m"
export CATALINA_OPTS="$CATALINA_OPTS `ruby resources/set_environment`"
env > env.log
PORT=-1
while getopts ":p:" opt; do
  case $opt in
    p)
      PORT=$OPTARG
      ;;
  esac
done
if [ $PORT -lt 0 ] ; then
  echo "Missing or invalid port (-p)"
  exit 1
fi
ruby resources/generate_server_xml $PORT
cd tomcat
./bin/catalina.sh run > ../logs/stdout.log 2> ../logs/stderr.log &
STARTED=$!
echo "$STARTED" >> ../run.pid
wait $STARTED
      EXPECTED
    end
  end

  it "requests the specified amount of memory from the JVM" do
    environment = { :resources => {:memory => 256} }
    stage(:spring, environment) do |staged_dir|
      start_script = File.join(staged_dir, 'startup')
      start_script.should be_executable_file
      script_body = File.read(start_script)
      script_body.should == <<-EXPECTED
#!/bin/bash
export CATALINA_OPTS="-Xms256m -Xmx256m"
export CATALINA_OPTS="$CATALINA_OPTS `ruby resources/set_environment`"
env > env.log
PORT=-1
while getopts ":p:" opt; do
  case $opt in
    p)
      PORT=$OPTARG
      ;;
  esac
done
if [ $PORT -lt 0 ] ; then
  echo "Missing or invalid port (-p)"
  exit 1
fi
ruby resources/generate_server_xml $PORT
cd tomcat
./bin/catalina.sh run > ../logs/stdout.log 2> ../logs/stderr.log &
STARTED=$!
echo "$STARTED" >> ../run.pid
wait $STARTED
      EXPECTED
    end
  end
end

describe "A Spring web application being staged without a web config" do
  before do
    app_fixture :spring_no_web_config
  end

  it "should fail" do
    lambda { stage(:spring){} }.should raise_error
  end
end

describe "A Spring web application being staged without a context-param in its web config and without a default application context config" do
  before do
    app_fixture :spring_no_context_config
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end
end

describe "A Spring web application being staged without a context-param in its web config and with a default application context config" do
  before(:all) do
    app_fixture :spring_default_appcontext_no_context_config
  end

  it "should have a context-param in its web config after staging" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      File.exist?(web_config_file).should == true

      web_config = Nokogiri::XML(open(web_config_file))
      context_param_node =  web_config.xpath("//context-param")
      context_param_node.length.should_not == 0
    end
  end

  it "should have a 'contextConfigLocation' where the default application context precedes the auto-reconfiguration context" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      context_param_name_node = web_config.xpath("//context-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      context_param_name_node.length.should_not == 0

      context_param_value_node = context_param_name_node.first.xpath("param-value")
      context_param_value_node.length.should_not == 0

      context_param_value = context_param_value_node.first.content
      default_context_index = context_param_value.index('/WEB-INF/applicationContext.xml')
      default_context_index.should_not == nil

      auto_reconfiguration_context_index = context_param_value.index('classpath:META-INF/cloud/cloudfoundry-auto-reconfiguration-context.xml')
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > default_context_index + "/WEB-INF/applicationContext.xml".length
    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

describe "A Spring web application being staged with a context-param but without a 'contextConfigLocation' param-name in its web config and with a default application context config" do
  before(:all) do
    app_fixture :spring_default_appcontext_context_param_no_context_config
  end

  it "should have a 'contextConfigLocation' where the default application context precedes the auto-reconfiguration context" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      context_param_name_node = web_config.xpath("//context-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      context_param_name_node.length.should_not == 0

      context_param_value_node = context_param_name_node.first.xpath("param-value")
      context_param_value_node.length.should_not == 0

      context_param_value = context_param_value_node.first.content
      default_context_index = context_param_value.index('/WEB-INF/applicationContext.xml')
      default_context_index.should_not == nil

      auto_reconfiguration_context_index = context_param_value.index('classpath:META-INF/cloud/cloudfoundry-auto-reconfiguration-context.xml')
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > default_context_index + "/WEB-INF/applicationContext.xml".length
    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

describe "A Spring web application being staged with a context-param containing a 'contextConfigLocation' of 'foo' in its web config" do
  before(:all) do
    app_fixture :spring_context_config_foo
  end

  it "should have the 'foo' context precede the auto-reconfiguration context in the 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      context_param_name_node = web_config.xpath("//context-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]").first
      context_param_value_node = context_param_name_node.xpath("param-value")
      context_param_value = context_param_value_node.first.content
      foo_index = context_param_value.index('foo')
      foo_index.should_not == nil

      auto_reconfiguration_context_index = context_param_value.index('classpath:META-INF/cloud/cloudfoundry-auto-reconfiguration-context.xml')
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > foo_index + "foo".length
    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

end

describe "A Spring web application being staged with a context-param containing a 'contextInitializerClasses' of 'foo' in its web config" do
  before(:all) do
    app_fixture :spring_context_initializer_foo
  end

  it "should have the 'foo' initializer precede the auto-reconfiguration initializer 'contextInitializerClasses' param-value" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', "foo, #{CLOUD_APPLICATION_CONTEXT_INITIALIZER}"
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

describe "A Spring web application being staged without a Spring DispatcherServlet in its web config" do
  before(:all) do
    app_fixture :spring_context_config_foo
  end

  it "should be staged" do
    lambda { stage(:spring){} }.should_not raise_error
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end
end

describe "A Spring web application being staged with a Spring DispatcherServlet in its web config that does not have a default servlet context config or an 'init-param' config" do
  before(:all) do
    app_fixture :spring_servlet_no_init_param
  end

  it "should have a init-param in its web config after staging" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      File.exist?(web_config_file).should == true

      web_config = Nokogiri::XML(open(web_config_file))
      init_param_node =  web_config.xpath("//init-param")
      init_param_node.length.should_not == 0
    end
  end

  it "should have a 'contextConfigLocation' that includes the auto-reconfiguration context in its init-param" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//init-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      auto_reconfiguration_context_index = init_param_value.index('classpath:META-INF/cloud/cloudfoundry-auto-reconfiguration-context.xml')
      auto_reconfiguration_context_index.should_not == nil
    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end
end

describe "A Spring web application being staged with a Spring DispatcherServlet in its web config and containing a default servlet context config but no 'init-param' config" do
  before(:all) do
    app_fixture :spring_default_servletcontext_no_init_param
  end

  it "should have a init-param in its web config after staging" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      File.exist?(web_config_file).should == true

      web_config = Nokogiri::XML(open(web_config_file))
      init_param_node =  web_config.xpath("//init-param")
      init_param_node.length.should_not == 0
    end
  end

  it "should have the default servlet context precede the auto-reconfiguration context in the DispatcherServlet's 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//init-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      dispatcher_servlet_index = init_param_value.index('/WEB-INF/dispatcher-servlet.xml')
      dispatcher_servlet_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index('classpath:META-INF/cloud/cloudfoundry-auto-reconfiguration-context.xml')
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > dispatcher_servlet_index + "/WEB-INF/dispatcher-servlet.xml".length

    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end
end

describe "A Spring web application being staged with a Spring DispatcherServlet in its web config and containing a default servlet context config but no 'contextConfigLocation' in its 'init-param' config" do
  before(:all) do
    app_fixture :spring_default_servletcontext_init_param_no_context_config
  end

  it "should have the default servlet context precede the auto-reconfiguration context in the DispatcherServlet's 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//init-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      dispatcher_servlet_index = init_param_value.index('/WEB-INF/dispatcher-servlet.xml')
      dispatcher_servlet_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index('classpath:META-INF/cloud/cloudfoundry-auto-reconfiguration-context.xml')
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > dispatcher_servlet_index + "/WEB-INF/dispatcher-servlet.xml".length

    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

describe "A Spring web application being staged with a Spring DispatcherServlet in its web config with an 'init-param' config containing a 'contextConfigLocation' of 'foo' in its web config" do
  before(:all) do
    app_fixture :spring_servlet_context_config_foo
  end

  it "should have the 'foo' context precede the auto-reconfiguration context in the DispatcherServlet's 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//init-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      foo_index = init_param_value.index('foo')
      foo_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index('classpath:META-INF/cloud/cloudfoundry-auto-reconfiguration-context.xml')
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > foo_index + "foo".length

    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end
end

describe "A Spring web application being staged with 2 Spring DispatcherServlet in its web config containing a default servlet context config but no 'init-param' configs" do
  before(:all) do
    app_fixture :spring_multiple_dispatcherservlets_no_init_param
  end

  it "should have 2 init-params in its web config after staging" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      File.exist?(web_config_file).should == true

      web_config = Nokogiri::XML(open(web_config_file))
      init_param_node =  web_config.xpath("//init-param")
      init_param_node.length.should == 2
    end
  end

  it "the 2 init-params in its web config after staging should be valid" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      File.exist?(web_config_file).should == true

      web_config = Nokogiri::XML(open(web_config_file))
      init_param_nodes =  web_config.xpath("//init-param")
      init_param_nodes.each do |init_param_node|
        init_param_name_node = init_param_node.xpath("param-name")
        init_param_name_node.length.should == 1

        init_param_value_node = init_param_node.xpath("param-value")
        init_param_value_node.length.should == 1

      end
    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

describe "A Spring web application being staged with 2 Spring DispatcherServlets in its web config with an 'init-param' config in each containing a 'contextConfigLocation' of 'foo' in its web config" do
  before(:all) do
    app_fixture :spring_multiple_dispatcherservlets_context_config_foo
  end

  it "should have the 'foo' context precede the auto-reconfiguration context in 2 the DispatcherServlet's 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_nodes = web_config.xpath("//init-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_nodes.length.should == 2

      init_param_value_nodes = web_config.xpath("//init-param/param-value")
      init_param_value_nodes.length.should == 2

      init_param_value_nodes.each do |init_param_value_node|
        init_param_value = init_param_value_node.content
        foo_index = init_param_value.index('foo')
        foo_index.should_not == nil

        auto_reconfiguration_context_index = init_param_value.index('classpath:META-INF/cloud/cloudfoundry-auto-reconfiguration-context.xml')
        auto_reconfiguration_context_index.should_not == nil

        auto_reconfiguration_context_index.should > foo_index + "foo".length
      end

    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end
end

describe "A Spring web application being staged using an AnnotationConfigWebApplicationContext in its web config and a contextConfigLocation of 'foo' specified" do
  before(:all) do
    app_fixture :spring_annotation_context_config_foo
  end

  it "should have the 'foo' context precede the AnnotationConfigWebApplicationContext in the 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//context-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      foo_index = init_param_value.index('foo')
      foo_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index(CLOUD_APP_ANNOTATION_CONFIG_CLASS)
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > foo_index + "foo".length
      auto_reconfiguration_context_index.should < foo_index + 5

    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

describe "A Spring web application being staged using an AnnotationConfigWebApplicationContext in its web config and a contextConfigLocation of 'foo' specified plus has a servlet init-param using an AnnotationConfigWebApplicationContext and a contextConfigLocation of 'bar'" do
  before(:all) do
    app_fixture :spring_annotation_context_config_and_servletcontext
  end

  it "should have the 'foo' context precede the AnnotationConfigWebApplicationContext in the 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//context-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      foo_index = init_param_value.index('foo')
      foo_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index(CLOUD_APP_ANNOTATION_CONFIG_CLASS)
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > foo_index + "foo".length
      auto_reconfiguration_context_index.should < foo_index + 5

    end
  end

  it "should have the 'bar' context precede the AnnotationConfigWebApplicationContext in the DispatcherServlet's 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//init-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      bar_index = init_param_value.index('bar')
      bar_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index(CLOUD_APP_ANNOTATION_CONFIG_CLASS)
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > bar_index + "bar".length
      auto_reconfiguration_context_index.should < bar_index + 5

    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

describe "A Spring web application being staged using a namespace and an AnnotationConfigWebApplicationContext in its web config and a contextConfigLocation of 'foo' specified plus has a servlet init-param using an AnnotationConfigWebApplicationContext and a contextConfigLocation of 'bar'" do
  before(:all) do
    app_fixture :spring_annotation_context_config_and_servletcontext_ns
  end

  it "should have the 'foo' context precede the AnnotationConfigWebApplicationContext in the 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//xmlns:context-param[contains(normalize-space(xmlns:param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("xmlns:param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      foo_index = init_param_value.index('foo')
      foo_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index(CLOUD_APP_ANNOTATION_CONFIG_CLASS)
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > foo_index + "foo".length
      auto_reconfiguration_context_index.should < foo_index + 5

    end
  end

  it "should have the 'bar' context precede the AnnotationConfigWebApplicationContext in the DispatcherServlet's 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//xmlns:init-param[contains(normalize-space(xmlns:param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("xmlns:param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      bar_index = init_param_value.index('bar')
      bar_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index(CLOUD_APP_ANNOTATION_CONFIG_CLASS)
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > bar_index + "bar".length
      auto_reconfiguration_context_index.should < bar_index + 5

    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER, "xmlns:"
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

describe "A Spring web application being staged using an AnnotationConfigWebApplicationContext in its web config and a dispatcher servlet that does not have a default servlet 'init-param' config" do
  before(:all) do
    app_fixture :spring_annotation_context_config_and_servletcontext_empty
  end

  it "should have the 'foo' context precede the AnnotationConfigWebApplicationContext in the 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//context-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      foo_index = init_param_value.index('foo')
      foo_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index(CLOUD_APP_ANNOTATION_CONFIG_CLASS)
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > foo_index + "foo".length
      auto_reconfiguration_context_index.should < foo_index + 5

    end
  end

  it "should have a init-param in its web config after staging" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      File.exist?(web_config_file).should == true

      web_config = Nokogiri::XML(open(web_config_file))
      init_param_node =  web_config.xpath("//init-param")
      init_param_node.length.should_not == 0
    end
  end

  it "should have the default servlet context precede the auto-reconfiguration context in the DispatcherServlet's 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//init-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      dispatcher_servlet_index = init_param_value.index('/WEB-INF/dispatcher-servlet.xml')
      dispatcher_servlet_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index('classpath:META-INF/cloud/cloudfoundry-auto-reconfiguration-context.xml')
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > dispatcher_servlet_index + "/WEB-INF/dispatcher-servlet.xml".length

    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

describe "A Spring web application being staged with a context-param but without a 'contextConfigLocation' param-name in its web config and using a dispatcher servlet that does have an 'init-param' config with an AnnotationConfigWebApplicationContext" do
  before(:all) do
    app_fixture :spring_annotation_context_config_empty_with_servletcontext
  end

  it "should have a 'contextConfigLocation' where the default application context precedes the auto-reconfiguration context" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      context_param_name_node = web_config.xpath("//context-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      context_param_name_node.length.should_not == 0

      context_param_value_node = context_param_name_node.first.xpath("param-value")
      context_param_value_node.length.should_not == 0

      context_param_value = context_param_value_node.first.content
      default_context_index = context_param_value.index('/WEB-INF/applicationContext.xml')
      default_context_index.should_not == nil

      auto_reconfiguration_context_index = context_param_value.index('classpath:META-INF/cloud/cloudfoundry-auto-reconfiguration-context.xml')
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > default_context_index + "/WEB-INF/applicationContext.xml".length
    end
  end

  it "should have the 'bar' context precede the AnnotationConfigWebApplicationContext in the DispatcherServlet's 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//init-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      bar_index = init_param_value.index('bar')
      bar_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index(CLOUD_APP_ANNOTATION_CONFIG_CLASS)
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > bar_index + "bar".length
      auto_reconfiguration_context_index.should < bar_index + 5

    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

describe "A Spring web application being staged using an AnnotationConfigWebApplicationContext in its servlet init-param and a contextConfigLocation of 'bar' specified" do
  before(:all) do
    app_fixture :spring_annotation_servletcontext_no_context_config
  end

  it "should have the 'bar' context precede the AnnotationConfigWebApplicationContext in the DispatcherServlet's 'contextConfigLocation' param-value" do
    stage :spring do |staged_dir|
      web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
      web_config = Nokogiri::XML(open(web_config_file))
      init_param_name_node = web_config.xpath("//init-param[contains(normalize-space(param-name), normalize-space('contextConfigLocation'))]")
      init_param_name_node.length.should_not == 0

      init_param_value_node = init_param_name_node.xpath("param-value")
      init_param_value_node.length.should_not == 0

      init_param_value = init_param_value_node.first.content
      bar_index = init_param_value.index('bar')
      bar_index.should_not == nil

      auto_reconfiguration_context_index = init_param_value.index(CLOUD_APP_ANNOTATION_CONFIG_CLASS)
      auto_reconfiguration_context_index.should_not == nil

      auto_reconfiguration_context_index.should > bar_index + "bar".length
      auto_reconfiguration_context_index.should < bar_index + 5

    end
  end

  it "should have a 'contextInitializerClasses' context-param with only the CloudApplicationContextInitializer" do
    stage :spring do |staged_dir|
      assert_context_param staged_dir, 'contextInitializerClasses', CLOUD_APPLICATION_CONTEXT_INITIALIZER
    end
  end

  it "should have the auto reconfiguration jar in the webapp lib path" do
    stage :spring do |staged_dir|
      auto_reconfig_jar_relative_path = "tomcat/webapps/ROOT/WEB-INF/lib/#{AUTOSTAGING_JAR}"
      auto_reconfiguration_jar_path = File.join(staged_dir, auto_reconfig_jar_relative_path)
      File.exist?(auto_reconfiguration_jar_path).should == true
    end
  end

end

def assert_context_param staged_dir, param_name, param_value, prefix=""
  web_config_file = File.join(staged_dir, 'tomcat/webapps/ROOT/WEB-INF/web.xml')
  web_config = Nokogiri::XML(open(web_config_file))
  context_param_name_node = web_config.xpath("//#{prefix}context-param[contains(normalize-space(#{prefix}param-name), normalize-space('#{param_name}'))]")
  context_param_name_node.length.should_not == 0

  context_param_value_node = context_param_name_node.first.xpath("#{prefix}param-value")
  context_param_value_node.length.should_not == 0

  context_param_value = context_param_value_node.first.content
  context_param_value.should == param_value
end
