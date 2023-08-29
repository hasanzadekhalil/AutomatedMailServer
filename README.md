Author
===
This project was made by Khalil Hasanzade with helping Mailu Docker Image.

Automated Mail Server
====
When you run the script, it will prompt you to set up the domain name and admin password. All you need to do is provide these details. The script will automatically handle the rest of the components' installation and configuration. The script performs the following tasks:

1. Installs curl if it's not already installed.
2. Checks if Docker is installed; if not, it proceeds with the installation.
3. Automatically detects your public IP address and includes it in the installation process.
4. Asks for the domain name and admin password from you, which it uses during the installation.
5. After completion, it provides the list of DNS records that need to be added.
6. Handles the installation of an SSL certificate.
   
The script automates these tasks, making the setup process smooth and efficient.

```
cd /tmp
git clone https://github.com/hasanzadekhalil/AutomatedMailServer.git
cd AutomatedMailServer
chmod +x install.sh
./install.sh
```

Credits
===

This Script using Mailu Docker Image.
