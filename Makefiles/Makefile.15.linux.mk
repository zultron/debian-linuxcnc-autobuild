###################################################
# 15. Linux kernel build rules

# This kernel can build featuresets for Xenomai and RTAI.  To hook
# dependencies into this build, add to these variables in the
# dependency's Makefile:
#
# LINUX_KERNEL_FEATURESETS :		Add names of enabled featuresets
# LINUX_KERNEL_FEATURESETS_DISABLED :	Add names of featuresets to disable
# LINUX_KERNEL_SOURCE_DEPS :		Add names of packages needed in the
#					chroot to configure the kernel
#					source package
# LINUX_KERNEL_DEPS_INDEP :		Distro target dependencies
# LINUX_KERNEL_DEPS :			Distro-arch or common target
#					dependencies

###################################################
# Variables that may change

# Linux vanilla tarball
LINUX_PKG_RELEASE = 1mk
LINUX_VERSION = 3.8.13
LINUX_URL = http://www.kernel.org/pub/linux/kernel/v3.0


###################################################
# Variables that should not change much
# (or auto-generated)

# Misc paths, filenames, executables
LINUX_TARBALL := linux-$(LINUX_VERSION).tar.xz
LINUX_TARBALL_DEBIAN_ORIG := linux_$(LINUX_VERSION).orig.tar.xz
LINUX_NAME_EXT := $(shell echo $(LINUX_VERSION) | sed 's/\.[0-9]*$$//')
LINUX_PKG_VERSION = $(LINUX_VERSION)-$(LINUX_PKG_RELEASE)~$(CODENAME)1


###################################################
# 15.1. Check out git submodule
stamps/15.1.linux-kernel-package-checkout: \
		stamps/0.1.base-builddeps
	@echo "===== 15.1. All variants: "\
	    "Checking out kernel Debian git repo ====="
	$(REASON)
#	# be sure the submodule has been checked out
	test -e git/kernel-rt-deb/.git || \
	    git submodule update --init git/kernel-rt-deb
	test -e git/kernel-rt-deb/.git
	touch $@

stamps/15.1.linux-kernel-package-checkout-clean: \
		$(call CA_EXPAND,\
			stamps/15.3.%.linux-kernel-deps-update-chroot-clean)
	@echo "15.1. All:  Clean linux kernel packaging git submodule stamp"
	rm -f stamps/15.1.linux-kernel-package-checkout

stamps/15.1.linux-kernel-package-checkout-squeaky: \
		stamps/15.1.linux-kernel-package-checkout-clean
	@echo "15.1. All:  Clean linux kernel packaging git submodule"
	rm -rf git/kernel-rt-deb; mkdir -p git/kernel-rt-deb
LINUX_SQUEAKY_ALL += stamps/15.1.linux-kernel-package-checkout-squeaky


###################################################
# 15.2. Download linux tarball
stamps/15.2.linux-kernel-tarball-downloaded: \
		stamps/0.1.base-builddeps
	@echo "===== 15.2. All variants: " \
	    "Downloading vanilla Linux tarball ====="
	$(REASON)
	rm -f dist/$(LINUX_TARBALL)
	wget $(LINUX_URL)/$(LINUX_TARBALL) -O dist/$(LINUX_TARBALL)
	touch $@
# This target is needed by linux-tools
LINUX_TARBALL_TARGET := stamps/15.2.linux-kernel-tarball-downloaded

stamps/15.2.linux-kernel-tarball-downloaded-clean: \
		$(call CA_EXPAND,\
			stamps/15.3.%.linux-kernel-deps-update-chroot-clean)
	@echo "15.2. All:  Clean up linux kernel tarball"
	rm -f dist/$(LINUX_TARBALL)
	rm -f stamps/15.2.linux-kernel-tarball-downloaded
LINUX_SQUEAKY_ALL += stamps/15.2.linux-kernel-tarball-downloaded


###################################################
# 15.3. Update chroot with dependent packages

# Any indep targets should be added to $(LINUX_KERNEL_DEPS_INDEP), and
# arch or all targets should be added to $(LINUX_KERNEL_DEPS)
$(call CA_TO_C_DEPS,stamps/15.3.%.linux-kernel-deps-update-chroot,\
	$(LINUX_KERNEL_DEPS_INDEP))
$(call CA_EXPAND,stamps/15.3.%.linux-kernel-deps-update-chroot): \
stamps/15.3.%.linux-kernel-deps-update-chroot: \
		stamps/15.1.linux-kernel-package-checkout \
		stamps/15.2.linux-kernel-tarball-downloaded \
		$(LINUX_KERNEL_DEPS)
	$(call UPDATE_CHROOT,15.3)
.PRECIOUS: $(call CA_EXPAND,stamps/15.3.%.linux-kernel-deps-update-chroot)

$(call CA_EXPAND,stamps/15.3.%.linux-kernel-deps-update-chroot-clean): \
stamps/15.3.%.linux-kernel-deps-update-chroot-clean:
	@echo "15.3. $(CA):  Clean linux kernel chroot deps update stamp"
	rm -f stamps/15.3.$(CA).linux-kernel-deps-update-chroot
$(call CA_TO_C_DEPS,stamps/15.3.%.linux-kernel-deps-update-chroot-clean,\
	stamps/15.5.%.linux-kernel-source-package-clean)

# Cleaning this cleans up all (non-squeaky) linux arch and indep artifacts
LINUX_CLEAN_ARCH := stamps/15.3.%.linux-kernel-deps-update-chroot-clean


###################################################
# 15.4. Unpack and configure Linux package source tree

# This has to be done in a chroot with the featureset packages
stamps/15.4.linux-kernel-package-configured: CODENAME = $(A_CODENAME)
stamps/15.4.linux-kernel-package-configured: ARCH = $(AN_ARCH)
stamps/15.4.linux-kernel-package-configured: \
		stamps/15.3.$(A_CHROOT).linux-kernel-deps-update-chroot
	@echo "===== 15.4. All:  Unpacking and configuring" \
	    " Linux source package ====="
	$(REASON)
#	# Starting clean, copy debian packaging and hardlink source tarball
	rm -rf $(SOURCEDIR)/linux/build; mkdir -p $(SOURCEDIR)/linux/build
	git --git-dir="git/kernel-rt-deb/.git" archive --prefix=debian/ HEAD \
	    | tar xCf $(SOURCEDIR)/linux/build -
#	# Hardlink linux tarball with Debian-format path name
	ln -sf $(TOPDIR)/dist/$(LINUX_TARBALL) \
	    $(SOURCEDIR)/linux/$(LINUX_TARBALL_DEBIAN_ORIG)
	cp --preserve=all dist/$(LINUX_TARBALL) \
	    $(BUILDRESULT)/$(LINUX_TARBALL_DEBIAN_ORIG)
#	# Configure the package in a chroot
	chmod +x pbuild/linux-unpacked-chroot-script.sh
	$(SUDO) INTERMEDIATE_REPO=ppa \
	    $(PBUILD) \
		--execute --bindmounts ${TOPDIR}/$(SOURCEDIR)/linux \
		$(PBUILD_ARGS) \
		pbuild/linux-unpacked-chroot-script.sh \
		    -d "$(LINUX_KERNEL_FEATURESETS_DISABLED)" \
		    -b "$(LINUX_KERNEL_SOURCE_DEPS)"
#	# Make copy of changelog for later munging
	cp --preserve=all $(SOURCEDIR)/linux/build/debian/changelog \
	    $(SOURCEDIR)/linux
#	# Build the source tree and clean up
	cd $(SOURCEDIR)/linux/build && debian/rules orig
	cd $(SOURCEDIR)/linux/build && debian/rules clean
	touch $@
.PRECIOUS: stamps/15.4.linux-kernel-package-configured

stamps/15.4.linux-kernel-package-configured-clean: \
		$(call C_EXPAND,stamps/15.5.%.linux-kernel-source-package-clean)
	@echo "15.4.  All: Clean configured linux kernel source directory"
	rm -rf $(SOURCEDIR)/linux
	rm -f $(BUILDRESULT)/$(LINUX_TARBALL_DEBIAN_ORIG)
	rm -f stamps/15.4.linux-kernel-package-configured
LINUX_CLEAN_ALL += stamps/15.4.linux-kernel-package-configured-clean


###################################################
# 15.5. Build Linux kernel source package for each distro
$(call C_EXPAND,stamps/15.5.%.linux-kernel-source-package): \
stamps/15.5.%.linux-kernel-source-package: \
		stamps/15.1.linux-kernel-package-checkout \
		stamps/15.4.linux-kernel-package-configured
	@echo "===== 15.5. $(CODENAME)-all: " \
	    "Building Linux source package ====="
	$(REASON)
#	# Restore original changelog
	cp --preserve=all $(SOURCEDIR)/linux/changelog \
	    $(SOURCEDIR)/linux/build/debian
#	# Add changelog entry
	cd $(SOURCEDIR)/linux/build && \
	    $(TOPDIR)/pbuild/tweak-pkg.sh \
	    $(CODENAME) $(LINUX_PKG_VERSION) "$(MAINTAINER)"
#	# Create source pkg
	cd $(SOURCEDIR)/linux/build && dpkg-source -i -I -b .
	mv $(SOURCEDIR)/linux/linux_$(LINUX_PKG_VERSION).debian.tar.xz \
	    $(SOURCEDIR)/linux/linux_$(LINUX_PKG_VERSION).dsc $(BUILDRESULT)
	touch $@
.PRECIOUS: $(call C_EXPAND,stamps/15.5.%.linux-kernel-source-package)

$(call C_EXPAND,stamps/15.5.%.linux-kernel-source-package-clean): \
stamps/15.5.%.linux-kernel-source-package-clean:
	@echo "15.5.  $(CODENAME):  Clean linux kernel source build"
	rm -f $(BUILDRESULT)/linux_$(LINUX_PKG_VERSION).debian.tar.xz
	rm -f $(BUILDRESULT)/linux_$(LINUX_PKG_VERSION).dsc
	rm -f stamps/15.5.linux-kernel-source-package
$(call C_TO_CA_DEPS,stamps/15.5.%.linux-kernel-source-package-clean,\
	stamps/15.6.%.linux-kernel-build-clean)

###################################################
# 15.6. Build kernel packages for each distro/arch
#
# Use the PPA with featureset devel packages
$(call CA_TO_C_DEPS,stamps/15.6.%.linux-kernel-build,\
	stamps/15.5.%.linux-kernel-source-package)

$(call CA_EXPAND,stamps/15.6.%.linux-kernel-build): \
stamps/15.6.%.linux-kernel-build: \
		stamps/15.3.%.linux-kernel-deps-update-chroot
	@echo "===== 15.6. $(CA):  Building Linux binary package ====="
	$(REASON)
	$(SUDO) INTERMEDIATE_REPO=ppa \
	    $(PBUILD) --build \
		$(PBUILD_ARGS) \
	        $(BUILDRESULT)/linux_$(LINUX_PKG_VERSION).dsc || \
	    (rm -f $@ && exit 1)
	touch $@
.PRECIOUS: $(call CA_EXPAND,stamps/15.6.%.linux-kernel-build)
LINUX_ARTIFACTS_ARCH += stamps/15.6.%.linux-kernel-build

$(call CA_EXPAND,stamps/15.6.%.linux-kernel-build-clean): \
stamps/15.6.%.linux-kernel-build-clean:
	@echo "15.6.  $(CA):  Clean linux kernel binary builds"
	rm -f $(wildcard $(BUILDRESULT)/linux-headers-*_$(LINUX_PKG_VERSION)_$(ARCH).deb)
	rm -f $(wildcard $(BUILDRESULT)/linux-image-*_$(LINUX_PKG_VERSION)_$(ARCH).deb)
	rm -f $(BUILDRESULT)/linux_$(LINUX_PKG_VERSION)-$(ARCH).build
	rm -f $(BUILDRESULT)/linux_$(LINUX_PKG_VERSION)_$(ARCH).changes
	rm -f stamps/15.6.$*.linux-kernel-build
$(call CA_TO_C_DEPS,stamps/15.6.%.linux-kernel-build-clean,\
	stamps/15.7.%.linux-kernel-ppa-clean)

###################################################
# 15.7. Add kernel packages to the PPA for each distro

# e.g.:
# linux-headers-3.8-1mk-common-xenomai.x86_3.8.13-1mk~wheezy1_i386.deb
# linux-headers-3.8-1mk-xenomai.x86-686-pae_3.8.13-1mk~wheezy1_i386.deb
# linux-image-3.8-1mk-xenomai.x86-686-pae_3.8.13-1mk~wheezy1_i386.deb
$(call C_TO_CA_DEPS,stamps/15.7.%.linux-kernel-ppa,\
	stamps/15.6.%.linux-kernel-build)
$(call C_EXPAND,stamps/15.7.%.linux-kernel-ppa): \
stamps/15.7.%.linux-kernel-ppa: \
		stamps/15.5.%.linux-kernel-source-package \
		stamps/0.3.all.ppa-init
	$(call BUILD_PPA,15.7,linux,\
	    $(BUILDRESULT)/linux_$(LINUX_PKG_VERSION).dsc,\
	    $(foreach a,$(call CODENAME_ARCHES,$(CODENAME)),$(wildcard\
		$(BUILDRESULT)/linux-headers-*_$(LINUX_PKG_VERSION)_$(a).deb \
		$(BUILDRESULT)/linux-image-*_$(LINUX_PKG_VERSION)_$(a).deb)))

# This is the final result of the linux kernel build
LINUX_INDEP := stamps/15.7.%.linux-kernel-ppa

$(call C_EXPAND,stamps/15.7.%.linux-kernel-ppa-clean): \
stamps/15.7.%.linux-kernel-ppa-clean:
	@echo "15.7.  $(CODENAME):  Clean linux kernel PPA stamp"
	rm -f stamps/15.7.%.linux-kernel-ppa-clean


###################################################
# 15.5. Wrap up

# Hook kernel build into final build
FINAL_DEPS_INDEP += $(LINUX_INDEP)
SQUEAKY_ALL += $(LINUX_SQUEAKY_ALL)
CLEAN_ARCH += $(LINUX_CLEAN_ARCH)
CLEAN_ALL += $(LINUX_CLEAN_ALL)

# Convenience target
linux:  $(call C_EXPAND,$(LINUX_INDEP))
LINUX_TARGET_ALL := "linux"
LINUX_DESC := "Convenience:  Build Linux packages for all distros"
LINUX_SECTION := packages
HELP_VARS += LINUX