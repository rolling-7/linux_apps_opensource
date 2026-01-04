# Rolling Linux apps
This is a Rolling linux apps set project for wwan devices.<br>
  **Flash service:** firmware update, switch, recovery.<br>
  **Ma service:** fccunlock(It is not open source).<br>
  **Config service:** OEM configuration function.<br>
  **Helper service:** provider dbus API for Flash/Ma/Config service.<br>

# License
The rolling_flash rolling_config  rolling_helper binaries are both LGPL 2.0, and rolling_ma_service is MIT.<br>

# Notice
  - Service must be used with fw_package. Before installing service, ensure that fw_package has been installed. Obtain the fw package from the corresponding OEM .<br>
  - fw_switch using fastboot so you can install fastboot with command `sudo apt-get install fastboot`<br>
  - fw_switch using gcab to decompress so you need install gcab with command `sudo apt-get install gcab` <br>
  - This application build only on ubuntu24.04 and runs on ubuntu24.04 or later, other ubuntu versions and other OS have unverified.
  - This application need modemmanager version 1.23.8 or later.

# Building on Ubuntu

## 1. Install dependence

- sudo apt install cmake<br>
- sudo apt install build-essential<br>
- sudo apt install -y pkg-config<br>
- sudo apt install libglib2.0-dev<br>
- sudo apt install libxml2-dev<br>
- sudo apt install libudev-dev<br>
- sudo apt install libmbim-glib-dev<br>
- sudo apt install libdbus-1-dev<br>
- sudo apt install libmm-glib-dev<br>
- sudo apt install libfwupd-dev<br>
- sudo apt install gcc<br>
- sudo apt install g++<br>
- sudo apt install -y rpm<br>
- sudo apt install 

## 2. build 
### method one: <br>
  - if build deb: <br>
    - run: <br>
      ./script/make_deb.sh deb rw101 lenovo <br>
  - if build rpm: <br>
    - run: <br>
      ./script/make_deb.sh rpm rw101 lenovo <br>

### method two: <br>
  - clean build evroment <br>
    rm -rf build <br>
  - if build deb: <br>
    cmake -S . -B build -DBUILD_DEB=yes -DPROJECT_BUILD=rw101 -DOEM_BUILD=lenovo -DBUILD_BY_LIB=1 <br>
  - if build rpm: <br>
    cmake -S . -B build -DBUILD_RPM=yes -DPROJECT_BUILD=rw101 -DOEM_BUILD=lenovo -DBUILD_BY_LIB=1 <br>
  - run build with: <br>
    cmake --build build <br>
  - pack with: <br>
    cd build <br>
    cpack <br>

## 3. if build ok need to install or uninstall
### if deb: <br>
  - install: <br>
    sudo dpkg -i linux-apps-qualcomm-rw101-lenovo_2.0.29_amd64.deb <br>
  - find package: <br>
    sudo dpkg -l | grep linux-apps <br>
  - uninstall: <br>
    sudo dpkg -p dpkg -P linux-apps-qualcomm-rw101-lenovo <br>
### if rpm: <br>
  - install: <br>
    sudo rpm -i --force linux-apps-qualcomm-rw101-lenovo_2.0.29_amd64.rpm <br>
  - find package: <br>
    dnf search "linux-apps" <br>
  - uninstall: <br>
    dnf remove **linux-apps** <br>

## 4. If using systemd
- load config file <br>
  sudo systemctl daemon-reload <br>
- enable service <br>
  sudo systemctl enable rolling_xxx.service <br>
  **examples:** sudo systemctl enable rolling_helper.service <br>
&emsp;&emsp;&emsp;&emsp;&emsp;sudo systemctl enable rolling_helper.service <br>
&emsp;&emsp;&emsp;&emsp;&emsp;sudo systemctl enable rolling_flash.service <br>
&emsp;&emsp;&emsp;&emsp;&emsp;sudo systemctl enable rolling_config.service <br>
**notices:** this step must be done,then systemd can find and start the service <br>
- start service <br>
	sudo systemctl start rolling_xxx.service <br>
- Get status<br>
	sudo systemctl status rolling_xxx.service<br>
- Stop service<br>
	sudo systemctl stop rolling_xxx.service<br>

# release history
- version:1.0.0<br>
  first version, upload to github.<br>
