import pandas as pd

def getExcelSheetHeaders(filePath):
    # Load the Excel file
    xls = pd.ExcelFile(filePath)

    # Initialize a dictionary to store sheet names and headers
    sheetHeaders = {}

    # Loop through each sheet in the Excel file
    for sheetName in xls.sheet_names:
        # Read the sheet into a DataFrame
        df = pd.read_excel(xls, sheet_name=sheetName)

        # Get the headers of the sheet
        headers = list(df.columns)

        # Store the headers in the dictionary
        sheetHeaders[sheetName] = headers

    return sheetHeaders

# Paths to your Excel files
animalPath = '0-Data/1-RawData/2-SourceData/Detailed-SourceData-Animal.xlsx'
cropPath = '0-Data/1-RawData/2-SourceData/Detailed-SourceData-Crop.xlsx'
sourcePath = '0-Data/1-RawData/2-SourceData/SourceData.xlsx'

# List of file paths
filePaths = [animalPath, cropPath, sourcePath]

# Process each file and print the sheet headers
for filePath in filePaths:
    print(f"Processing file: {filePath}")
    sheetHeaders = getExcelSheetHeaders(filePath)
    for sheet, headers in sheetHeaders.items():
        print(f"  Sheet: {sheet}")
        print(f"  Headers: {headers}")
        print()

