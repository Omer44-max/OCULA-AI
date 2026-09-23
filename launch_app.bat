@echo off
title Launching DR Screening System...
start "" "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -nosplash -minimize -r "cd('C:\Users\ASUS\.gemini\antigravity\scratch\DR_Screening_System'); addpath(genpath(pwd)); DR_Screening_App;"
exit
