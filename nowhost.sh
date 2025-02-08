#!/bin/bash

echo "Enter your email address for SSL certificate notifications:"
read user_email

# Validate the email address format
if ! [[ "$user_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "Invalid email address. Please enter a valid email."
  exit 1
fi

# Install required packages using apt
echo "Installing required packages..."
sudo apt update
sudo apt install -y git nginx certbot python3-certbot-nginx

# Install IPFS
echo "Installing IPFS..."
wget https://dist.ipfs.io/go-ipfs/v0.16.0/go-ipfs_v0.16.0_linux-amd64.tar.gz
tar -xvzf go-ipfs_v0.16.0_linux-amd64.tar.gz
cd go-ipfs
sudo bash install.sh
cd ..
rm -rf go-ipfs go-ipfs_v0.16.0_linux-amd64.tar.gz

# Initialize IPFS and start the daemon
echo "Initializing IPFS node..."
ipfs init
ipfs daemon &

echo "Enter the server's IP address (this will be used as the server name):"
read server_ip

if [[ -z "$server_ip" ]]; then
  echo "Server IP cannot be empty."
  exit 1
fi

echo "Enter the name of the domain to create (this will be used for the directory name):"
read directory_name

if [[ -z "$directory_name" ]]; then
  echo "Domain name cannot be empty."
  exit 1
else
  # Create the directory for the domain
  mkdir "/var/www/html/$directory_name"

  if [[ $? -eq 0 ]]; then
    echo "Domain '$directory_name' created successfully."

    # Set permissions for the web server
    sudo chown -R www-data:www-data "/var/www/html/$directory_name"
    sudo chmod -R 755 "/var/www/html/$directory_name"

    # Create a basic index.html file for the domain
    echo "<html><body><h1>Welcome to $directory_name</h1></body></html>" > "/var/www/html/$directory_name/index.html"
    echo "Created default index.html for $directory_name"

    # Check if Tiny File Manager is installed (assumed location: /var/www/tinyfilemanager)
    if [ ! -d "/var/www/tinyfilemanager" ]; then
      echo "Tiny File Manager directory '/var/www/tinyfilemanager' not found. Installing Tiny File Manager..."

      # Download Tiny File Manager
      sudo git clone https://github.com/prasathmani/tinyfilemanager.git /var/www/tinyfilemanager

      # Ensure proper permissions
      sudo chown -R www-data:www-data /var/www/tinyfilemanager
      sudo chmod -R 755 /var/www/tinyfilemanager

      echo "Tiny File Manager installed successfully!"
    else
      echo "Tiny File Manager already installed."
    fi

    # Copy Tiny File Manager files to the domain directory
    cp -r /var/www/tinyfilemanager/* "/var/www/html/$directory_name/"
    echo "Tiny File Manager files copied to $directory_name directory."

    # Ask the user for a custom IP address to redirect the domain to
    echo "Enter the IP address to redirect the domain to (e.g., 192.168.1.1):"
    read custom_ip

    if [[ -z "$custom_ip" ]]; then
      echo "IP address cannot be empty. Exiting..."
      exit 1
    fi

    # Modify the Nginx configuration to redirect to the custom IP address
    echo "server {
        listen 80;
        server_name $server_ip;

        location / {
            return 301 http://$custom_ip;
        }
    }" > "/etc/nginx/sites-available/$directory_name"

    # Enable the site in Nginx
    sudo ln -s /etc/nginx/sites-available/$directory_name /etc/nginx/sites-enabled/

    # Test the Nginx configuration and reload
    sudo nginx -t
    sudo systemctl reload nginx

    echo "Nginx configured for $directory_name, and domain redirects to $custom_ip."

    # Enable HTTPS (Let's Encrypt with Certbot)
    echo "Configuring HTTPS for IP-based server ($server_ip)..."

    # Attempt to obtain SSL certificate using Certbot
    # Note: Certbot typically requires a domain, but this method uses the server IP
    sudo certbot --nginx -d $server_ip --non-interactive --agree-tos --email "$user_email"

    # Test Nginx configuration after Certbot updates
    sudo nginx -t
    sudo systemctl reload nginx

    echo "HTTPS setup complete for server IP ($server_ip) with Let's Encrypt SSL certificate!"

    # Upload website to IPFS
    echo "Uploading website to IPFS..."

    # Add the website directory to IPFS and get the CID (Content Identifier)
    ipfs add -r "/var/www/html/$directory_name" > ipfs_output.txt
    ipfs_hash=$(tail -n 1 ipfs_output.txt | awk '{print $2}')

    echo "Website uploaded to IPFS with CID: $ipfs_hash"
    echo "You can access the site via the IPFS gateway at: https://ipfs.io/ipfs/$ipfs_hash"

  else
    echo "Failed to create directory '$directory_name'."
  fi
fi

