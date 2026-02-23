import xml.etree.ElementTree as ET
import xml.dom.minidom

def writeXMLfromGDF(gdf_segments, gdf_outlet_points, gdf_outlet_lines, gdf_outlet_lines_estuary, gdf_estuary,
                    outputFile, config):
    # Ensure consistent data types for matching
    gdf_segments['RiverSegN'] = gdf_segments['RiverSegN'].astype(str)
    gdf_outlet_points['RiverSeg'] = gdf_outlet_points['RiverSeg'].astype(str)

    # Create the root element
    root = ET.Element('LFES',
                      name=config['systemName'],
                      scenario=config['scenario'],
                      refArchitecture="Land-River System",
                      dataState="raw",
                      inputDataFormat="default",
                      version=config['version'],
                      verboseMode=config['verboseMode'],
                      analyzeSoS="false",
                      outputFileType=config["outputFileType"])

    # Add Operand elements for water, nitrogen, phosphorus, and sediment
    for operand_name in ["water", "nitrogen", "phosphorous", "sediment"]:
        ET.SubElement(root, 'Operand', operandName=operand_name, operandType="matter")

    # Iterate over the land-river segments to create Transformation Resources
    for idx, row in gdf_segments.iterrows():
        transformationResource = ET.SubElement(root, 'TransformationResource',
                                transformationResourceName=f"Land Segment {row['LndRvrSegN']}",
                                gpsX=str(row['x_riverSeg']),
                                gpsY=str(row['y_riverSeg']),
                                decisionMaker="",
                                autonomous="true",
                                riverSeg=str(row['RiverSegN']),
                                county=str(row['FIPS_NHL']))

        # Check for matching outlet points
        matching_outlet_points = gdf_outlet_points[gdf_outlet_points['RiverSeg'] == row['RiverSegN']]
        has_outlet = not matching_outlet_points.empty

        # Create a separate Transformation Process for water
        transformationProcessWater = ET.SubElement(transformationResource, 'TransformationProcess',
                                                   name="accept water",
                                                   status="true" if has_outlet else "false",
                                                   inputOperand="water",
                                                   inputOperandWeight="1",
                                                   outputOperand="water",
                                                   outputOperandWeight="1",
                                                   precip=str(row['PRECIP']),
                                                   meanPrecip=str(row['MEANPRECIP']))

        # Create a combined Transformation Process for nitrogen, phosphorus, and sediment
        transformationProcessOther = ET.SubElement(transformationResource, 'TransformationProcess',
                                                   name="accept nitrogen, phosphorus, and sediment",
                                                   status="true",
                                                   inputOperand="nitrogen,phosphorous,sediment",
                                                   inputOperandWeight="1,1,1",
                                                   outputOperand="nitrogen,phosphorous,sediment",
                                                   outputOperandWeight="1,1,1")

        # Create Transportation Process if an outlet exists
        if has_outlet:
            outlet_point = matching_outlet_points.iloc[0]
            transportationProcess = ET.SubElement(transformationResource, 'TransportationProcess',
                                                   name="transport to outlet",
                                                   status="true",
                                                   origin=f"Land Segment {row['LndRvrSegN']}",
                                                   destination=f"Outlet {outlet_point['RiverSeg']}",
                                                   ref="water,nitrogen,phosphorous,sediment",
                                                   inputOperand="water,nitrogen,phosphorous,sediment",
                                                   inputOperandWeight="1,1,1,1",
                                                   outputOperand="water,nitrogen,phosphorous,sediment",
                                                   outputOperandWeight="1,1,1,1")
        else:
            print(f"Land Segment with RiverSegN {row['RiverSegN']} has no outlet point.")

    # Create Independent Buffers for each outlet point
    for idx, row in gdf_outlet_points.iterrows():
        independentBuffer = ET.SubElement(root, 'IndependentBuffer',
                               independentBufferName=f"Outlet {row['RiverSeg']}",
                               gpsX=str(row.geometry.x),
                               gpsY=str(row.geometry.y),
                               decisionMaker="",
                               autonomous="true")

    # Add the Estuary as an Independent Buffer
    estuary = gdf_estuary.iloc[0]
    independentBuffer = ET.SubElement(root, 'IndependentBuffer',
                               independentBufferName="Estuary 1",
                               gpsX=str(estuary.geometry.centroid.x),
                               gpsY=str(estuary.geometry.centroid.y),
                               decisionMaker="",
                               autonomous="true")

    # Create Transportation Resources for outlet point connections
    for idx, row in gdf_outlet_lines.iterrows():
        transportationResource = ET.SubElement(root, 'TransportationResource',
                                    transportationResourceName=f"River Segment {row['from']} to {row['to']}",
                                    decisionMaker="",
                                    autonomous="true")

        transportationProcess = ET.SubElement(transportationResource, 'TransportationProcess',
                                               name="transport",
                                               status="true",
                                               origin=f"Outlet {row['from']}",
                                               destination=f"Outlet {row['to']}",
                                               ref="water,nitrogen,phosphorous,sediment",
                                               inputOperand="water,nitrogen,phosphorous,sediment",
                                               inputOperandWeight="1,1,1,1",
                                               outputOperand="water,nitrogen,phosphorous,sediment",
                                               outputOperandWeight="1,1,1,1")

    # Create Transportation Resources for outlet connections to the estuary
    for idx, row in gdf_outlet_lines_estuary.iterrows():
        transportationResource = ET.SubElement(root, 'TransportationResource',
                                    transportationResourceName=f"Outlet {row['from']} to Estuary",
                                    decisionMaker="",
                                    autonomous="true")

        transportationProcess = ET.SubElement(transportationResource, 'TransportationProcess',
                                               name="transport to estuary",
                                               status="true",
                                               origin=f"Outlet {row['from']}",
                                               destination="Estuary 1",
                                               ref="water,nitrogen,phosphorous,sediment",
                                               inputOperand="water,nitrogen,phosphorous,sediment",
                                               inputOperandWeight="1,1,1,1",
                                               outputOperand="water,nitrogen,phosphorous,sediment",
                                               outputOperandWeight="1,1,1,1")

    # Convert the ElementTree to a string and pretty-print it
    XMLstr = ET.tostring(root, encoding='utf-8')
    parsedXML = xml.dom.minidom.parseString(XMLstr)
    prettyXMLstr = parsedXML.toprettyxml(indent="    ")

    # Write the pretty-printed XML to a file
    with open(outputFile, 'w', encoding='utf-8') as xml_file:
        xml_file.write(prettyXMLstr)

    print("XML file has been created.")