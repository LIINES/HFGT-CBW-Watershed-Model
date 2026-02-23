import os
import pandas as pd


def extractSegmentId(geoStr):
    return geoStr.split('(')[0]


def processData(directoryPath):
    allData = []

    scenarioDir = os.path.join(directoryPath, '1-ScenarioData')
    for fileName in os.listdir(scenarioDir):
        if fileName.endswith('.xlsx'):
            filePath = os.path.join(scenarioDir, fileName)

            # Load datasets
            detailedLoads = pd.read_excel(filePath, sheet_name='Detailed Loads')
            landBmps = pd.read_excel(filePath, sheet_name='Land BMPs')
            animalBmps = pd.read_excel(filePath, sheet_name='Animal BMPs')
            manureTreatmentBmps = pd.read_excel(filePath, sheet_name='Manure Treatment BMPs')

            # Extract consistent identifiers
            detailedLoads['SegmentID'] = detailedLoads['Geography'].apply(extractSegmentId)
            landBmps['SegmentID'] = landBmps['Geography'].apply(extractSegmentId)
            manureTreatmentBmps['SegmentIDFrom'] = manureTreatmentBmps['GeographyFrom'].apply(extractSegmentId)
            manureTreatmentBmps['SegmentIDTo'] = manureTreatmentBmps['GeographyTo'].apply(extractSegmentId)

            # Merge data
            mergedData = pd.merge(detailedLoads, landBmps, on='SegmentID', how='left')
            mergedData = pd.merge(mergedData, animalBmps, left_on='SegmentID', right_on='SegmentID', how='left')
            mergedData = pd.merge(mergedData, manureTreatmentBmps, left_on='SegmentID', right_on='SegmentIDFrom',
                                  how='left')

            # Append to the list of all data
            allData.append(mergedData)

    # Concatenate all data into a single DataFrame
    combinedData = pd.concat(allData, ignore_index=True)

    # Save intermediate data
    combinedData.to_csv('0-Data/2-IntermediateData/mergedData.csv', index=False)


if __name__ == "__main__":
    processData('0-Data/1-RawData/')