FROM python:3.10

# Set environment variables for Python
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# Install SSH, VNC, and other dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    procps \
    openssh-server \
    sudo \
    tightvncserver \
    x11vnc \
    xvfb \
    fluxbox \
    wget \
    xterm \
    nano \
    cron \
    gosu \
    telnet \
    firefox-esr \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Setup display environment variable for VNC
ENV DISPLAY :1

# Set up SSH server
RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

# Expose the SSH and VNC ports
EXPOSE 22
# EXPOSE 5901

# Create and switch to a new user
RUN useradd -m trader -s /bin/bash && \
    echo 'trader:trader' | chpasswd && \
    mkdir -p /home/trader/.ssh && \
    chown -R trader:trader /home/trader && \
    chmod 700 /home/trader/.ssh

# Use the build argument to set the authorized_keys
COPY combined_keys.pub /home/trader/.ssh/authorized_keys
RUN chown trader:trader /home/trader/.ssh/authorized_keys && \
    chmod 600 /home/trader/.ssh/authorized_keys
    
# Copy the crontab file and entrypoint script as root
COPY crontab /home/trader/crontab
COPY entrypoint.sh /entrypoint.sh

# Set permissions and crontab as root
RUN chmod 0644 /home/trader/crontab && \
    chmod +x /entrypoint.sh && \
    crontab -u trader /home/trader/crontab
 
# Create directories and set ownership
RUN mkdir /home/trader/ibc && \
    mkdir /home/trader/ibc/logs && \
    mkdir /opt/ibc && \
    chown -R trader:trader /home/trader/ibc && \
    chown -R trader:trader /opt/ibc

# Copy config.ini and change ownership
COPY config.ini /home/trader/ibc/config.ini
RUN chown trader:trader /home/trader/ibc/config.ini

# Copy IBC files and set permissions
COPY ibc/ /opt/ibc/
RUN chmod +x /opt/ibc/gatewaystart.sh && \
    chmod +x /opt/ibc/commandsend.sh && \
    chmod +x /opt/ibc/scripts/displaybannerandlaunch.sh && \
    chmod +x /opt/ibc/scripts/ibcstart.sh
    
# Copy the IB Gateway installation script
COPY ibgateway-latest-standalone-linux-x64.sh /home/trader/

# Set permissions on the script as root
RUN chmod +x /home/trader/ibgateway-latest-standalone-linux-x64.sh

# Set the time zone by creating a symbolic link to the appropriate zoneinfo file
# This was causing issues before where CRON would run the jobs in UTC even though
# TZ was set as New York - this lets cron run on EST time.
RUN ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

# Setup supervisor for PySystemTrade logging (alt to systemd)

# Create supervisor configuration directory
RUN mkdir -p /etc/supervisor/conf.d

# Add the configuration file for log_server
COPY log_server.conf /etc/supervisor/conf.d/log_server.conf

# Add the main supervisor configuration file
# COPY supervisord.conf /etc/supervisor/supervisord.conf

# Switch to trader for running the application
USER trader

# Copy the .env file to the user's home directory
COPY .env /home/trader/.env

# Append the sourcing command to the end of .profile and export variables
RUN echo "set -a; source /home/trader/.env; set +a" >> /home/trader/.profile


# Create necessary directories
RUN mkdir -p /home/trader/echos \
             /home/trader/data/mongo_dump \
             /home/trader/data/backups_csv \
             /home/trader/data/backtests \
             /home/trader/data/reports \
             /home/trader/data/offsystem_backup \
             /home/trader/logs

# Set the working directory to the user's pysystemtrade directory
WORKDIR /home/trader/pysystemtrade

# Install Python dependencies and Jupyter
COPY pysystemtrade/requirements.txt /home/trader/pysystemtrade
RUN pip install --no-cache-dir -r requirements.txt

#For barchart
RUN pip install requests    
    
# Setup IB Gateway and IBC
RUN bash /home/trader/ibgateway-latest-standalone-linux-x64.sh -dir /home/trader/Jts/ibgateway/1027 -q

#Can we switch back?
USER root

ENTRYPOINT ["/entrypoint.sh"]
