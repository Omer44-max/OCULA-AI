Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "C:\Users\ASUS\.gemini\antigravity\scratch\DR_Screening_System"
WshShell.Run """C:\Program Files\MATLAB\R2026a\bin\matlab.exe"" -nosplash -nodesktop -sd ""C:\Users\ASUS\.gemini\antigravity\scratch\DR_Screening_System"" -r ""DR_Screening_App;""", 0, False
