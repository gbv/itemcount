debian-clean:
	fakeroot debian/rules clean

depencencies:
	carton install

debian-package:
	dpkg-buildpackage -b -us -uc -rfakeroot
	mv ../itemcount_* .
