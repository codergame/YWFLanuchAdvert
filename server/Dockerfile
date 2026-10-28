FROM tomcat:10.1-jdk11
ENV LAUNCHADVERT_HOME=/data/launchadvert
ENV LAUNCHADVERT_ADMIN_USER=admin
ENV LAUNCHADVERT_ADMIN_PASSWORD=admin
RUN mkdir -p /data/launchadvert
COPY target/lanuchadvert.war /usr/local/tomcat/webapps/ROOT.war
EXPOSE 8080
