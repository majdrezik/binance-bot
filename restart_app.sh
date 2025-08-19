#!/bin/bash

sudo systemctl daemon-reload
sudo systemctl restart tv-trader
sudo systemctl status tv-trader