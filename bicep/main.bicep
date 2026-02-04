@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Prefix used for naming resources')
param prefix string = 'threeTier'

@description('Admin username for all VMs')
param adminUsername string = 'azureuser'

@secure()
@description('Admin password for all VMs (min 12 chars recommended)')
param adminPassword string

@secure()
@description('Password used for MySQL app user and MySQL root hardening')
param mysqlAppPassword string

@description('CIDR range allowed to SSH into VMs (e.g., 203.0.113.45/32)')
param allowedAdminCidr string

// Addressing
var vnetCidr = '10.0.0.0/16'
var webSubnetCidr = '10.0.1.0/24'
var appSubnetCidr = '10.0.2.0/24'
var dbSubnetCidr  = '10.0.3.0/24'

// Static private IPs
var webPrivateIp = '10.0.1.4'
var appPrivateIp = '10.0.2.4'
var dbPrivateIp  = '10.0.3.4'

// Common
var vmSize = 'Standard_B2s'

// Images (Ubuntu 22.04 LTS Gen2)
var ubuntuPublisher = 'Canonical'
var ubuntuOffer     = '0001-com-ubuntu-server-jammy'
var ubuntuSku       = '22_04-lts-gen2'
var ubuntuVersion   = 'latest'

// ============== NSGs ==============
resource nsgWeb 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${prefix}-web-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Allow HTTP from Internet'
        }
      }
      {
        name: 'Allow-SSH-Admin'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: allowedAdminCidr
          destinationAddressPrefix: '*'
          description: 'Allow SSH from admin IP'
        }
      }
    ]
  }
}

resource nsgApp 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${prefix}-app-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-8080-from-Web'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceAddressPrefix: webSubnetCidr
          destinationAddressPrefix: '*'
          description: 'Allow App API from Web subnet'
        }
      }
      {
        name: 'Allow-SSH-Admin'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: allowedAdminCidr
          destinationAddressPrefix: '*'
          description: 'Allow SSH from admin IP'
        }
      }
    ]
  }
}

resource nsgDb 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${prefix}-db-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-MySQL-from-App'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: appSubnetCidr
          destinationAddressPrefix: '*'
          description: 'Allow MySQL from App subnet'
        }
      }
      {
        name: 'Allow-SSH-Admin'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: allowedAdminCidr
          destinationAddressPrefix: '*'
          description: 'Allow SSH from admin IP'
        }
      }
    ]
  }
}

// ============== VNet & Subnets ==============
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetCidr
      ]
    }
    subnets: [
      {
        name: 'web'
        properties: {
          addressPrefix: webSubnetCidr
          networkSecurityGroup: {
            id: nsgWeb.id
          }
        }
      }
      {
        name: 'app'
        properties: {
          addressPrefix: appSubnetCidr
          networkSecurityGroup: {
            id: nsgApp.id
          }
        }
      }
      {
        name: 'db'
        properties: {
          addressPrefix: dbSubnetCidr
          networkSecurityGroup: {
            id: nsgDb.id
          }
        }
      }
    ]
  }
}

// Helper to get subnet IDs
var webSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'web')
var appSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'app')
var dbSubnetId  = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'db')

// ============== Public IP for Web ==============
resource webPublicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: '${prefix}-web-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

// ============== NICs ==============
resource webNic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: '${prefix}-web-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: webSubnetId
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: webPrivateIp
          publicIPAddress: {
            id: webPublicIp.id
          }
        }
      }
    ]
  }
}

resource appNic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: '${prefix}-app-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: appSubnetId
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: appPrivateIp
        }
      }
    ]
  }
}

resource dbNic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: '${prefix}-db-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: dbSubnetId
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: dbPrivateIp
        }
      }
    ]
  }
}

// ============== CustomData (cloud-init) ==============

// WEB: Nginx + reverse proxy to app
var webUserData = base64('''
#cloud-config
runcmd:
  - apt-get update
  - apt-get install -y nginx
  - bash -lc "cat > /var/www/html/index.html << 'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>3-tier demo</title>
<style>
  body { font-family: Arial, sans-serif; margin: 2rem; }
  code { background: #f5f5f5; padding: 2px 4px; }
</style>
</head>
<body>
  <h1>Azure 3-tier demo</h1>
  <p>Web → App → DB</p>
  <div id="result">Loading...</div>
  <script>
    fetch('/api/')
      .then(r => r.json())
      .then(j => {
        document.getElementById('result').innerText = JSON.stringify(j, null, 2);
      })
      .catch(e => {
        document.getElementById('result').innerText = 'Error: ' + e;
      });
  </script>
</body>
</html>
HTML"
  - bash -lc "cat > /etc/nginx/sites-available/default << 'NGINX'
server {
  listen 80 default_server;
  listen [::]:80 default_server;

  root /var/www/html;
  index index.html;

  server_name _;

  location / {
    try_files $uri $uri/ =404;
  }

  # Reverse-proxy API calls to App VM (private)
  location /api/ {
    proxy_pass http://${appPrivateIp}:8080/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_cache_bypass $http_upgrade;
  }
}
NGINX"
  - systemctl restart nginx
''')

// APP: Python Flask + MySQL connector, systemd service
var appUserData = base64('''
#cloud-config
runcmd:
  - apt-get update
  - apt-get install -y python3 python3-pip
  - pip3 install flask mysql-connector-python
  - mkdir -p /opt/app
  - bash -lc "cat > /opt/app/app.py << 'PY'
import os
from flask import Flask, jsonify
import mysql.connector

DB_HOST = os.environ.get('DB_HOST')
DB_USER = os.environ.get('DB_USER', 'appuser')
DB_PASSWORD = os.environ.get('DB_PASSWORD')
DB_NAME = os.environ.get('DB_NAME', 'demodb')

app = Flask(__name__)

@app.get('/health')
def health():
    return jsonify(status='ok')

@app.get('/')
def root():
    try:
        conn = mysql.connector.connect(host=DB_HOST, user=DB_USER, password=DB_PASSWORD, database=DB_NAME)
        cursor = conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM items;')
        count = cursor.fetchone()[0]
        cursor.close()
