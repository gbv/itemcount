debian/itemcount.1: README.md
	grep -v '^\[!' $< | pandoc -s -t man -M title="ITEMCOUNT(1) Manual" -o $@

debian-clean:
	fakeroot debian/rules clean

depencencies:
	carton install

debian-package:
	dpkg-buildpackage -b -us -uc -rfakeroot
	mv ../itemcount_* .
