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

    # === Operands: ONLY nitrogen & phosphorus ===
    operands = [
        {"name": "nitrogen", "type": "matter"},
        {"name": "phosphorus", "type": "matter"},
    ]
    for operand in operands:
        ET.SubElement(root, 'Operand', operandName=operand["name"], operandType=operand["type"])

    # Helpers
    def is_agricultural(row):
        major = str(row.get('Major', '')).lower()
        minor = str(row.get('Minor', '')).lower()
        return ('agric' in major) or ('agric' in minor)

    def is_developed(row):
        major = str(row.get('Major', '')).lower()
        minor = str(row.get('Minor', '')).lower()
        return ('develop' in major) or ('develop' in minor)

    # Track created names to avoid duplicates
    created_transformation_resources = set()
    created_independent_buffers = set()
    created_transportation_resources = set()

    # Create TransformationResources for all segments
    for _, row in gdf_segments.iterrows():
        resource_name = f"Land Segment {row['LndRvrSegN']}"
        if resource_name in created_transformation_resources:
            continue

        # Create the TransformationResource
        created_transformation_resources.add(resource_name)
        tr = ET.SubElement(root, 'TransformationResource',
                           transformationResourceName=resource_name,
                           gpsX=str(row['x_LRseg']),
                           gpsY=str(row['y_LRseg']),
                           decisionMaker="",
                           autonomous="true",
                           Major=str(row.get('Major', '')),
                           Minor=str(row.get('Minor', '')),
                           UniqID=str(row.get('UniqID', '')),
                           DSID=str(row.get('DSID', '')),
                           Flow=str(row.get('Flow', '')),
                           RiverSeg_l=str(row.get('RiverSeg_l', '')),
                           TidalWater=str(row.get('TidalWater', '')),
                           MajMin=str(row.get('MajMin', '')),
                           Region=str(row.get('Region', '')),
                           Watershed=str(row.get('Watershed', '')),
                           MajBas=str(row.get('MajBas', '')),
                           MinBas=str(row.get('MinBas', '')),
                           RiverSimu=str(row.get('RiverSimu', '')),
                           RiverName=str(row.get('RiverName', '')),
                           CBSEG_92=str(row.get('CBSEG_92', '')),
                           FIPS=str(row.get('FIPS', '')),
                           ST=str(row.get('ST', '')),
                           CNTYNAME=str(row.get('CNTYNAME', '')),
                           CBW=str(row.get('CBW', '')),
                           FIPS_NHL=str(row.get('FIPS_NHL', '')),
                           PRECIP=str(row.get('PRECIP', '')),
                           MEANPRECIP=str(row.get('MEANPRECIP', '')),
                           LndRvrSeg=str(row.get('LndRvrSeg', '')),
                           Acres=str(row.get('Acres', '')),
                           HGMR=str(row.get('HGMR', '')),
                           index_righ=str(row.get('index_righ', '')),
                           RiverSegN=str(row.get('RiverSegN', '')),
                           LndRvrSegN=str(row.get('LndRvrSegN', '')),
                           x_riverSeg=str(row.get('x_riverSeg', '')),
                           y_riverSeg=str(row.get('y_riverSeg', '')),
                           x_county=str(row.get('x_county', '')),
                           y_county=str(row.get('y_county', '')),
                           x_LRseg=str(row.get('x_LRseg', '')),
                           y_LRseg=str(row.get('y_LRseg', '')),
                           geometry=str(row.get('geometry', ''))
        )

        # Sector-specific ACCEPT processes for N & P (no water/sediment)
        for sector in ("agricultural", "developed"):
            for operand in ("nitrogen", "phosphorus"):
                ET.SubElement(tr, 'TransformationProcess',
                              name=f"accept {sector} {operand}",
                              status="true",
                              inputOperand="",
                              inputOperandWeight="0",
                              outputOperand=operand,
                              outputOperandWeight="1")

        # Transport to outlet only if there is a matching outlet point
        matching_outlet_points = gdf_outlet_points[gdf_outlet_points['RiverSeg'] == row['RiverSegN']]
        if matching_outlet_points.empty:
            # No outlet → no transport processes
            continue

        outlet_point = matching_outlet_points.iloc[0]
        destination_name = f"Outlet {outlet_point['RiverSeg']}"

        # Transportation processes (only N & P)
        for operand in operands:
            ET.SubElement(tr, 'TransportationProcess',
                          name=f"transport {operand['name']}",
                          status="true",
                          origin=resource_name,
                          destination=destination_name,
                          ref=operand['name'],
                          inputOperand=operand['name'],
                          inputOperandWeight="1",
                          outputOperand=operand['name'],
                          outputOperandWeight="1")

    # IndependentBuffers for outlet points
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

    # Estuary
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

    # TransportationResources (outlet → outlet)
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

        for operand in operands:
            ET.SubElement(tr, 'TransportationProcess',
                          name=f"transport {operand['name']}",
                          status="true",
                          origin=f"Outlet {row['from']}",
                          destination=f"Outlet {row['to']}",
                          ref=operand['name'],
                          inputOperand=operand['name'],
                          inputOperandWeight="1",
                          outputOperand=operand['name'],
                          outputOperandWeight="1")

    # TransportationResources (outlet → estuary-adjacent outlet, if present)
    for _, row in gdf_outlet_lines_estuary.iterrows():
        resource_name_1 = f"River Segment {row['from']} to {row['to']}"
        if resource_name_1 not in created_transportation_resources:
            created_transportation_resources.add(resource_name_1)
            tr = ET.SubElement(root, 'TransportationResource',
                               transportationResourceName=resource_name_1,
                               decisionMaker="",
                               autonomous="true")
            for operand in operands:
                ET.SubElement(tr, 'TransportationProcess',
                              name=f"transport {operand['name']}",
                              status="true",
                              origin=f"Outlet {row['from']}",
                              destination=f"Outlet {row['to']}",
                              ref=operand['name'],
                              inputOperand=operand['name'],
                              inputOperandWeight="1",
                              outputOperand=operand['name'],
                              outputOperandWeight="1")

    # TransportationResources (terminal outlets _0000 → estuary)
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

        for operand in operands:
            ET.SubElement(tr, 'TransportationProcess',
                          name=f"transport {operand['name']}",
                          status="true",
                          origin=from_outlet,
                          destination=estuary_name,
                          ref=operand['name'],
                          inputOperand=operand['name'],
                          inputOperandWeight="1",
                          outputOperand=operand['name'],
                          outputOperandWeight="1")

    # Pretty-print and write
    xml_str = ET.tostring(root, encoding='utf-8')
    parsed = xml.dom.minidom.parseString(xml_str)
    pretty_str = parsed.toprettyxml(indent="    ")

    with open(outputFile, 'w', encoding='utf-8') as f:
        f.write(pretty_str)

    print("XML file has been created successfully.")