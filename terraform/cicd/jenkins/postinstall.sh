#!/bin/bash

version=2.25
filename=jenkins_${version}_all.deb

redmine_ip=$1
redmine_version=$2
gerrit_ip=$3

apt-get update -y
apt-get install -y openjdk-7-jdk daemon nginx
wget -q -O - https://pkg.jenkins.io/debian/jenkins-ci.org.key | apt-key add -
echo deb http://pkg.jenkins.io/debian binary/ > /etc/apt/sources.list.d/jenkins.list
apt-get update -y
wget  http://pkg.jenkins.io/debian/binary/$filename
dpkg -i $filename
rm $filename

rm /etc/nginx/sites-available/default
cat <<EOL > /etc/nginx/sites-available/jenkins
upstream app_server {
    server 127.0.0.1:8080 fail_timeout=0;
}

server {
    listen 80;
    listen [::]:80 default ipv6only=on;
    server_name ci.yourcompany.com;

    location / {
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$http_host;
        proxy_redirect off;

        if (!-f \$request_filename) {
            proxy_pass http://app_server;
            break;
        }
    }
}
EOL

ln -s /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/
service nginx restart

echo $version > /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion
sed -i "s|127.0.0.1 localhost|127.0.0.1 localhost $(hostname)|g" /etc/hosts

# Install plugins

wget http://updates.jenkins-ci.org/latest/redmine.hpi -P /var/lib/jenkins/plugins
wget http://updates.jenkins-ci.org/latest/subversion.hpi -P /var/lib/jenkins/plugins
wget http://updates.jenkins-ci.org/latest/mapdb-api.hpi -P /var/lib/jenkins/plugins
wget http://updates.jenkins-ci.org/latest/credentials.hpi -P /var/lib/jenkins/plugins
wget http://updates.jenkins-ci.org/latest/ssh-credentials.hpi -P /var/lib/jenkins/plugins
wget http://updates.jenkins-ci.org/latest/scm-api.hpi -P /var/lib/jenkins/plugins
wget http://updates.jenkins-ci.org/latest/structs.hpi -P /var/lib/jenkins/plugins
wget http://updates.jenkins-ci.org/latest/workflow-step-api.hpi -P /var/lib/jenkins/plugins
wget http://updates.jenkins-ci.org/latest/workflow-scm-step.hpi -P /var/lib/jenkins/plugins

wget http://updates.jenkins-ci.org/latest/gerrit-trigger.hpi -P /var/lib/jenkins/plugins

apt-get install -y git maven
redmine_oauth_folder=/tmp/redmine-oauth-plugin
git clone https://github.com/mallowlabs/redmine-oauth-plugin.git $redmine_oauth_folder
pushd $redmine_oauth_folder
mvn package
export JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64/
mv target/redmine-oauth.hpi /var/lib/jenkins/plugins/
popd


cd /var/lib/jenkins/
# Configure Redmine
cat <<EOL > hudson.plugins.redmine.RedmineProjectProperty.xml
<?xml version='1.0' encoding='UTF-8'?>
<hudson.plugins.redmine.RedmineProjectProperty_-DescriptorImpl plugin="redmine@0.15">
  <redmineWebsites>
    <hudson.plugins.redmine.RedmineWebsiteConfig>
      <name>redmine</name>
      <baseUrl>http://$redmine_ip/</baseUrl>
      <versionNumber>$redmine_version</versionNumber>
    </hudson.plugins.redmine.RedmineWebsiteConfig>
  </redmineWebsites>
</hudson.plugins.redmine.RedmineProjectProperty_-DescriptorImpl>
EOL

cat <<EOL > gerrit-trigger.xml
<?xml version='1.0' encoding='UTF-8'?>
<com.sonyericsson.hudson.plugins.gerrit.trigger.PluginImpl plugin="gerrit-trigger@2.22.0">
  <servers class="java.util.concurrent.CopyOnWriteArrayList">
    <com.sonyericsson.hudson.plugins.gerrit.trigger.GerritServer>
      <name>gerrit</name>
      <noConnectionOnStartup>false</noConnectionOnStartup>
      <config class="com.sonyericsson.hudson.plugins.gerrit.trigger.config.Config">
        <gerritHostName>$gerrit_ip</gerritHostName>
        <gerritSshPort>29418</gerritSshPort>
        <gerritProxy></gerritProxy>
        <gerritUserName>jenkins</gerritUserName>
        <gerritEMail></gerritEMail>
        <gerritAuthKeyFile>/var/lib/jenkins/.ssh/id_rsa</gerritAuthKeyFile>
        <gerritAuthKeyFilePassword>f+BwOT8JcD9bpti9rVi5OQ==</gerritAuthKeyFilePassword>
        <useRestApi>false</useRestApi>
        <restCodeReview>false</restCodeReview>
        <restVerified>false</restVerified>
        <gerritVerifiedCmdBuildSuccessful>gerrit review &lt;CHANGE&gt;,&lt;PATCHSET&gt; --message &apos;Build Successful &lt;BUILDS_STATS&gt;&apos; --verified &lt;VERIFIED&gt; --code-review &lt;CODE_REVIEW&gt;</gerritVerifiedCmdBuildSuccessful>
        <gerritVerifiedCmdBuildUnstable>gerrit review &lt;CHANGE&gt;,&lt;PATCHSET&gt; --message &apos;Build Unstable &lt;BUILDS_STATS&gt;&apos; --verified &lt;VERIFIED&gt; --code-review &lt;CODE_REVIEW&gt;</gerritVerifiedCmdBuildUnstable>
        <gerritVerifiedCmdBuildFailed>gerrit review &lt;CHANGE&gt;,&lt;PATCHSET&gt; --message &apos;Build Failed &lt;BUILDS_STATS&gt;&apos; --verified &lt;VERIFIED&gt; --code-review &lt;CODE_REVIEW&gt;</gerritVerifiedCmdBuildFailed>
        <gerritVerifiedCmdBuildStarted>gerrit review &lt;CHANGE&gt;,&lt;PATCHSET&gt; --message &apos;Build Started &lt;BUILDURL&gt; &lt;STARTED_STATS&gt;&apos; --verified &lt;VERIFIED&gt; --code-review &lt;CODE_REVIEW&gt;</gerritVerifiedCmdBuildStarted>
        <gerritVerifiedCmdBuildNotBuilt>gerrit review &lt;CHANGE&gt;,&lt;PATCHSET&gt; --message &apos;No Builds Executed &lt;BUILDS_STATS&gt;&apos; --verified &lt;VERIFIED&gt; --code-review &lt;CODE_REVIEW&gt;</gerritVerifiedCmdBuildNotBuilt>
        <gerritFrontEndUrl>http://$gerrit_ip/</gerritFrontEndUrl>
        <gerritBuildStartedVerifiedValue>0</gerritBuildStartedVerifiedValue>
        <gerritBuildSuccessfulVerifiedValue>1</gerritBuildSuccessfulVerifiedValue>
        <gerritBuildFailedVerifiedValue>-1</gerritBuildFailedVerifiedValue>
        <gerritBuildUnstableVerifiedValue>0</gerritBuildUnstableVerifiedValue>
        <gerritBuildNotBuiltVerifiedValue>0</gerritBuildNotBuiltVerifiedValue>
        <gerritBuildStartedCodeReviewValue>0</gerritBuildStartedCodeReviewValue>
        <gerritBuildSuccessfulCodeReviewValue>0</gerritBuildSuccessfulCodeReviewValue>
        <gerritBuildFailedCodeReviewValue>0</gerritBuildFailedCodeReviewValue>
        <gerritBuildUnstableCodeReviewValue>-1</gerritBuildUnstableCodeReviewValue>
        <gerritBuildNotBuiltCodeReviewValue>0</gerritBuildNotBuiltCodeReviewValue>
        <enableManualTrigger>true</enableManualTrigger>
        <enablePluginMessages>true</enablePluginMessages>
        <buildScheduleDelay>3</buildScheduleDelay>
        <dynamicConfigRefreshInterval>30</dynamicConfigRefreshInterval>
        <enableProjectAutoCompletion>true</enableProjectAutoCompletion>
        <projectListRefreshInterval>3600</projectListRefreshInterval>
        <projectListFetchDelay>0</projectListFetchDelay>
        <categories class="linked-list">
          <com.sonyericsson.hudson.plugins.gerrit.trigger.VerdictCategory>
            <verdictValue>Code-Review</verdictValue>
            <verdictDescription>Code Review</verdictDescription>
          </com.sonyericsson.hudson.plugins.gerrit.trigger.VerdictCategory>
          <com.sonyericsson.hudson.plugins.gerrit.trigger.VerdictCategory>
            <verdictValue>Verified</verdictValue>
            <verdictDescription>Verified</verdictDescription>
          </com.sonyericsson.hudson.plugins.gerrit.trigger.VerdictCategory>
        </categories>
        <replicationConfig>
          <enableReplication>false</enableReplication>
          <slaves class="linked-list"/>
          <enableSlaveSelectionInJobs>false</enableSlaveSelectionInJobs>
        </replicationConfig>
        <watchdogTimeoutMinutes>0</watchdogTimeoutMinutes>
        <watchTimeExceptionData>
          <daysOfWeek/>
          <timesOfDay class="linked-list"/>
        </watchTimeExceptionData>
        <notificationLevel>ALL</notificationLevel>
        <buildCurrentPatchesOnly>
          <enabled>false</enabled>
          <abortNewPatchsets>false</abortNewPatchsets>
          <abortManualPatchsets>false</abortManualPatchsets>
        </buildCurrentPatchesOnly>
      </config>
    </com.sonyericsson.hudson.plugins.gerrit.trigger.GerritServer>
  </servers>
  <pluginConfig>
    <numberOfReceivingWorkerThreads>3</numberOfReceivingWorkerThreads>
    <numberOfSendingWorkerThreads>1</numberOfSendingWorkerThreads>
    <replicationCacheExpirationInMinutes>360</replicationCacheExpirationInMinutes>
  </pluginConfig>
</com.sonyericsson.hudson.plugins.gerrit.trigger.PluginImpl>
EOL

cat <<EOL > config.xml
<?xml version='1.0' encoding='UTF-8'?>
<hudson>
  <disabledAdministrativeMonitors/>
  <version>1.0</version>
  <numExecutors>2</numExecutors>
  <mode>NORMAL</mode>
  <useSecurity>true</useSecurity>
  <authorizationStrategy class="hudson.security.AuthorizationStrategy\$Unsecured"/>
  <securityRealm class="org.jenkinsci.plugins.RedmineSecurityRealm">
    <redmineUrl>http://${redmine_ip}</redmineUrl>
    <clientID></clientID>
    <clientSecret></clientSecret>
  </securityRealm>
  <disableRememberMe>false</disableRememberMe>
  <projectNamingStrategy class="jenkins.model.ProjectNamingStrategy\$DefaultProjectNamingStrategy"/>
  <workspaceDir>\${ITEM_ROOTDIR}/workspace</workspaceDir>
  <buildsDir>\${ITEM_ROOTDIR}/builds</buildsDir>
  <markupFormatter class="hudson.markup.EscapedMarkupFormatter"/>
  <jdks/>
  <viewsTabBar class="hudson.views.DefaultViewsTabBar"/>
  <myViewsTabBar class="hudson.views.DefaultMyViewsTabBar"/>
  <clouds/>
  <scmCheckoutRetryCount>0</scmCheckoutRetryCount>
  <views>
    <hudson.model.AllView>
      <owner class="hudson" reference="../../.."/>
      <name>All</name>
      <filterExecutors>false</filterExecutors>
      <filterQueue>false</filterQueue>
      <properties class="hudson.model.View$PropertyList"/>
    </hudson.model.AllView>
  </views>
  <primaryView>All</primaryView>
  <slaveAgentPort>0</slaveAgentPort>
  <label></label>
  <nodeProperties/>
  <globalNodeProperties/>
</hudson>
EOL

cat <<EOL > jenkins.security.QueueItemAuthenticatorConfiguration.xml
<?xml version='1.0' encoding='UTF-8'?>
<jenkins.security.QueueItemAuthenticatorConfiguration>
  <authenticators/>
</jenkins.security.QueueItemAuthenticatorConfiguration>
EOL

chown jenkins:jenkins -R /var/lib/jenkins/
service jenkins restart
echo false > secrets/slave-to-master-security-kill-switch
service jenkins restart

su jenkins -c "ssh-keygen -b 2048 -t rsa -f /var/lib/jenkins/.ssh/id_rsa -q -N \"\""
