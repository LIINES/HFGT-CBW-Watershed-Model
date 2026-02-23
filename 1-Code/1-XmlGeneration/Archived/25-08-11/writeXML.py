import xml.etree.ElementTree as ET
import xml.dom.minidom
def writeXMLfromGDF(gdf_segments, gdf_outlet_points, gdf_outlet_lines, gdf_outlet_lines_estuary, gdf_estuary,
                             outputFile, config):

    # Ensure consistent types for joins
    gdf_segments['RiverSegN'] = gdf_segments['RiverSegN'].astype(str)
    gdf_outlet_points['RiverSeg'] = gdf_outlet_points['RiverSeg'].astype(str)

    # Initialize XML root
    root = ET.Element('LFES',
                      name=config['systemName'],
                      scenario=config['scenario'],
                      refArchitecture=config['refArchitecture'],
                      dataState=config['dataState'],
                      inputDataFormat=config['inputDataFormat'],
                      version=config['version'],
                      verboseMode=config['verboseMode'],
                      analysisMethod=config['analysisMethod'],
                      outputDataFormat=config["outputDataFormat"],
                      outputFileType=config["outputFileType"],
                      simHorizon=config['simHorizon'],
                      deltaT=config['deltaT'])

    # Define operands
    operands = [
        {"name": "water", "type": "matter"},
        {"name": "nitrogen", "type": "matter"},
        {"name": "phosphorus", "type": "matter"},
        {"name": "sediment", "type": "matter"}
    ]

    # Create operand elements
    for operand in operands:
        ET.SubElement(root, 'Operand', operandName=operand["name"], operandType=operand["type"])

    # Track created names to avoid duplicates
    created_transformation_resources = set()
    created_independent_buffers = set()
    created_transportation_resources = set()

    # Create TransformationResources for all segments
    for _, row in gdf_segments.iterrows():
        resource_name = f"Land Segment {row['LndRvrSegN']}"
        if resource_name in created_transformation_resources:
            continue

        # Check if there is an outlet for this segment
        matching_outlet_points = gdf_outlet_points[gdf_outlet_points['RiverSeg'] == row['RiverSegN']]

        # Create the TransformationResource regardless
        created_transformation_resources.add(resource_name)
        tr = ET.SubElement(root, 'TransformationResource',
                           transformationResourceName=resource_name,
                           gpsX=str(row['x_LRseg']),
                           gpsY=str(row['y_LRseg']),
                           decisionMaker="",
                           autonomous="true",
                           # riverSeg=str(row['RiverSegN']),
                           # county=str(row['FIPS_NHL']),
                           Major = str(row['Major']),
                           Minor = str(row['Minor']),
                           UniqID = str(row['UniqID']),
                           DSID = str(row['DSID']),
                           Flow = str(row['Flow']),
                           RiverSeg_l = str(row['RiverSeg_l']),
                           TidalWater = str(row['TidalWater']),
                           MajMin = str(row['MajMin']),
                           Region = str(row['Region']),
                           Watershed = str(row['Watershed']),
                           MajBas = str(row['MajBas']),
                           MinBas = str(row['MinBas']),
                           RiverSimu = str(row['RiverSimu']),
                           RiverName = str(row['RiverName']),
                           CBSEG_92 = str(row['CBSEG_92']),
                           FIPS = str(row['FIPS']),
                           ST = str(row['ST']),
                           CNTYNAME = str(row['CNTYNAME']),
                           CBW = str(row['CBW']),
                           FIPS_NHL = str(row['FIPS_NHL']),
                           PRECIP = str(row['PRECIP']),
                           MEANPRECIP = str(row['MEANPRECIP']),
                           LndRvrSeg = str(row['LndRvrSeg']),
                           Acres = str(row['Acres']),
                           HGMR = str(row['HGMR']),
                           index_righ = str(row['index_righ']),
                           RiverSegN = str(row['RiverSegN']),
                           LndRvrSegN = str(row['LndRvrSegN']),
                           x_riverSeg = str(row['x_riverSeg']),
                           y_riverSeg = str(row['y_riverSeg']),
                           x_county = str(row['x_county']),
                           y_county = str(row['y_county']),
                           x_LRseg = str(row['x_LRseg']),
                           y_LRseg = str(row['y_LRseg']),
                           geometry = str(row['geometry'])
        )


        # Create accept processes for all operands (regardless of outlet)
        for operand in operands:
            operand_name = operand["name"]

            # Create accept process for this operand
            accept_process = ET.SubElement(tr, 'TransformationProcess',
                                           name=f"accept {operand_name}",
                                           status="true",
                                           inputOperand="",
                                           inputOperandWeight="0",
                                           outputOperand=operand_name,
                                           outputOperandWeight="1")

            # Add operand-specific attributes for water
            if operand_name == "water":
                accept_process.set("precip", str(row['PRECIP']))
                accept_process.set("meanPrecip", str(row['MEANPRECIP']))

        # Only add transport processes if there's a matching outlet point
        if matching_outlet_points.empty:
            print(f"No transport processes for Land Segment {row['LndRvrSegN']} (no outlet point)")
            continue

        # Get the outlet point and create transport processes
        outlet_point = matching_outlet_points.iloc[0]
        destination_name = f"Outlet {outlet_point['RiverSeg']}"

        for operand in operands:
            operand_name = operand["name"]

            # Create transport process for this operand
            ET.SubElement(tr, 'TransportationProcess',
                          name=f"transport {operand_name}",
                          status="true",
                          origin=resource_name,
                          destination=destination_name,
                          ref=operand_name,
                          inputOperand=operand_name,
                          inputOperandWeight="1",
                          outputOperand=operand_name,
                          outputOperandWeight="1")

    # Add IndependentBuffers for outlet points
    for _, row in gdf_outlet_points.iterrows():
        buffer_name = f"Outlet {row['RiverSeg']}"
        if buffer_name in created_independent_buffers:
            continue
        created_independent_buffers.add(buffer_name)

        ET.SubElement(root, 'IndependentBuffer',
                      independentBufferName=buffer_name,
                      gpsX=str(row.geometry.x),
                      gpsY=str(row.geometry.y),
                      decisionMaker="",
                      autonomous="true")

    # Add Estuary
    estuary = gdf_estuary.iloc[0]
    estuary_name = "Estuary 1"
    if estuary_name not in created_independent_buffers:
        created_independent_buffers.add(estuary_name)
        ET.SubElement(root, 'IndependentBuffer',
                      independentBufferName=estuary_name,
                      gpsX=str(estuary.geometry.centroid.x),
                      gpsY=str(estuary.geometry.centroid.y),
                      decisionMaker="",
                      autonomous="true")

    # Add TransportationResources (outlet → outlet)
    # Add TransportationResources (outlet → outlet)
    assigned_outlet_connections = set()

    for _, row in gdf_outlet_lines.iterrows():
        resource_name = f"River Segment {row['from']} to {row['to']}"
        if resource_name in created_transportation_resources or (row['from'], row['to']) in assigned_outlet_connections:
            continue
        created_transportation_resources.add(resource_name)
        assigned_outlet_connections.add((row['from'], row['to']))

        tr = ET.SubElement(root, 'TransportationResource',
                           transportationResourceName=resource_name,
                           decisionMaker="",
                           autonomous="true")

        # Create transport processes for all operands
        for operand in operands:
            operand_name = operand["name"]
            ET.SubElement(tr, 'TransportationProcess',
                          name=f"transport {operand_name}",
                          status="true",
                          origin=f"Outlet {row['from']}",
                          destination=f"Outlet {row['to']}",
                          ref=operand_name,
                          inputOperand=operand_name,
                          inputOperandWeight="1",
                          outputOperand=operand_name,
                          outputOperandWeight="1")

    # Add TransportationResources (outlet to estuary)
    assigned_to_estuary = set()

    for _, row in gdf_outlet_lines_estuary.iterrows():
        # Connect outlet to estuary-adjacent outlet (if applicable)
        resource_name_1 = f"River Segment {row['from']} to {row['to']}"
        if resource_name_1 not in created_transportation_resources:
            created_transportation_resources.add(resource_name_1)

            tr = ET.SubElement(root, 'TransportationResource',
                               transportationResourceName=resource_name_1,
                               decisionMaker="",
                               autonomous="true")

            # Create transport processes for all operands
            for operand in operands:
                operand_name = operand["name"]
                ET.SubElement(tr, 'TransportationProcess',
                              name=f"transport {operand_name}",
                              status="true",
                              origin=f"Outlet {row['from']}",
                              destination=f"Outlet {row['to']}",
                              ref=operand_name,
                              inputOperand=operand_name,
                              inputOperandWeight="1",
                              outputOperand=operand_name,
                              outputOperandWeight="1")

    # Add TransportationResources from outlet points ending in _0000 to the estuary
    for _, row in gdf_outlet_points.iterrows():
        outlet_id = str(row["RiverSeg"]).strip()
        if not outlet_id.endswith("_0000"):
            continue

        from_outlet = f"Outlet {outlet_id}"
        resource_name = f"River Segment {outlet_id} to {estuary_name}"
        if resource_name in created_transportation_resources:
            continue
        created_transportation_resources.add(resource_name)

        tr = ET.SubElement(root, 'TransportationResource',
                           transportationResourceName=resource_name,
                           decisionMaker="",
                           autonomous="true")

        # Create transport processes for all operands
        for operand in operands:
            operand_name = operand["name"]
            ET.SubElement(tr, 'TransportationProcess',
                          name=f"transport {operand_name}",
                          status="true",
                          origin=from_outlet,
                          destination=estuary_name,
                          ref=operand_name,
                          inputOperand=operand_name,
                          inputOperandWeight="1",
                          outputOperand=operand_name,
                          outputOperandWeight="1")

    # Pretty-print and write
    xml_str = ET.tostring(root, encoding='utf-8')
    parsed = xml.dom.minidom.parseString(xml_str)
    pretty_str = parsed.toprettyxml(indent="    ")

    with open(outputFile, 'w', encoding='utf-8') as f:
        f.write(pretty_str)

    print("XML file has been created successfully.")