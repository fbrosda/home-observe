SERVICE_NAME = home-observe
SERVICE_FILE = $(SERVICE_NAME).service
SYSTEMD_DIR = /etc/systemd/system

install:
	cp $(SERVICE_FILE) $(SYSTEMD_DIR)/

uninstall:
	-rm $(SYSTEMD_DIR)/$(SERVICE_FILE)

.PHONY: install uninstall
