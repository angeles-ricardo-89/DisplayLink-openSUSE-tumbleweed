# DisplayLink-openSUSE-tumbleweed

Original DisplayLink driver modified in order to be able to be built for OpenSUSE Tumbleweed.

Tested on OpenSuse Tumbleweed 5.1.5-1-default

Kernel headers are required in order to build drivers correctly.

evdi driver were modified in order to be able to compile it on 5.1.5, modified source code is inside back_evdi-5.1.26-src/ folder

```bash
cd back_evdi-5.1.26-src
tar -cvf ../evdi-5.1.26-src.tar.gz *
./displaylink-installer.sh
```
I'm not including any .spkg file (firmware file), you have to extract them from the original DisplayLink's ubuntu driver https://www.displaylink.com/downloads/ubuntu and copy them to the folder where you downloaded "my" version.


```bash
./displaylink-driver-5.1.26.run --noexec --keep
```

I'm using a Dell D3100 docking station using this driver, and it's working fine and I hope this will work for you.
