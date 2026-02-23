import xml.etree.ElementTree as ET
import xml.dom.minidom


def safe_str(value):
    """Convert value to string, replacing None with 'NOTHING' for Python/Julia compatibility."""
    if value is None or str(value) == 'None':
        return 'NOTHING'
    return str(value)


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
                      outputFileType=config["outputFileType"],
                      optimizer=config['optimizer'],
                      simHorizon=config['simHorizon'],
                      deltaT=config['deltaT'],
                      hasESN_STF1 = "true",
                      hasESN_STF2 = "false",
                      hasESN_Duration = "false",
                      hasBufferUpperBound = "false",
                      hasBufferLowerBound = "false",
                      hasBufferInitCond = "true",
                      hasBufferFinalCond = "false",
                      hasBufferLinearCost = "false",
                      hasBufferQuadCost = "false",
                      hasProcessUpperBoundFlowNeg = "false",
                      hasProcessUpperBoundFlowPos = "false",
                      hasProcessUpperBoundRamp = "false",
                      hasProcessUpperBoundStock = "false",
                      hasProcessLowerBoundFlowNeg = "false",
                      hasProcessLowerBoundFlowPos = "false",
                      hasProcessLowerBoundRamp = "false",
                      hasProcessLowerBoundStock = "false",
                      hasProcessInitCond = "false",
                      hasProcessFinalCond = "false",
                      hasProcessLinearCostFlowNeg = "false",
                      hasProcessLinearCostFlowPos = "false",
                      hasProcessLinearCostStock = "false",
                      hasProcessQuadCostFlowNeg = "false",
                      hasProcessQuadCostFlowPos = "false",
                      hasProcessQuadCostStock = "false",
                      hasProcessRamp = "false",
                      hasProcessDuration = "false",
                      hasProcessValues = "true"
    )

    # === Operands: ONLY nitrogen & phosphorus ===
    operands = [
        {"name": "nitrogen", "type": "matter","netName":"deliver nitrogen"},
        {"name": "phosphorus", "type": "matter","netName":"deliver phosphorus"},
    ]
    for operand in operands:
        ET.SubElement(root, 'Operand', operandName=operand["name"], operandType=operand["type"],
                      operandNetName=operand["netName"],status = "true",
                      hasOperandNet_STF1 = "false", hasOperandNet_STF2 = "false",
                      hasOperandNet_Duration = "false", hasSyncMatNeg = "false",
                      hasSyncMatPos = "false", hasPlaceUpperBound = "false", hasPlaceLowerBound = "false",
                      hasPlaceLinearCost = "false", hasPlaceQuadCost = "false", hasPlaceFinalConds = "false",
                      hasPlaceInitConds = "false", hasTransitionLinearCostFlowNeg = "false",
                      hasTransitionLinearCostFlowPos = "false", hasTransitionLinearCostStock = "false",
                      hasTransitionQuadCostFlowNeg = "false", hasTransitionQuadCostFlowPos = "false",
                      hasTransitionQuadCostStock = "false", hasTransitionLowerBoundFlowNeg = "false",
                      hasTransitionLowerBoundFlowPos = "false", hasTransitionLowerBoundStock = "false",
                      hasTransitionUpperBoundFlowNeg = "false", hasTransitionUpperBoundFlowPos = "false",
                      hasTransitionUpperBoundStock = "false", hasTransitionCost = "false",
                      hasTransitionDurationConds = "false", hasTransitionFinalConds = "false",
                      hasTransitionInitConds = "false",
        )

    # Helpers
    def is_agricultural(row):
        major = safe_str(row.get('Major', '')).lower()
        minor = safe_str(row.get('Minor', '')).lower()
        return ('agric' in major) or ('agric' in minor)

    def is_developed(row):
        major = safe_str(row.get('Major', '')).lower()
        minor = safe_str(row.get('Minor', '')).lower()
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
                           gpsX=safe_str(row['x_LRseg']),
                           gpsY=safe_str(row['y_LRseg']),
                           decisionMaker="",
                           autonomous="true",
                           initCond="0,0",
                           Major=safe_str(row.get('Major', '')),
                           Minor=safe_str(row.get('Minor', '')),
                           UniqID=safe_str(row.get('UniqID', '')),
                           DSID=safe_str(row.get('DSID', '')),
                           Flow=safe_str(row.get('Flow', '')),
                           RiverSeg_l=safe_str(row.get('RiverSeg_l', '')),
                           TidalWater=safe_str(row.get('TidalWater', '')),
                           MajMin=safe_str(row.get('MajMin', '')),
                           Region=safe_str(row.get('Region', '')),
                           Watershed=safe_str(row.get('Watershed', '')),
                           MajBas=safe_str(row.get('MajBas', '')),
                           MinBas=safe_str(row.get('MinBas', '')),
                           RiverSimu=safe_str(row.get('RiverSimu', '')),
                           RiverName=safe_str(row.get('RiverName', '')),
                           CBSEG_92=safe_str(row.get('CBSEG_92', '')),
                           FIPS=safe_str(row.get('FIPS', '')),
                           ST=safe_str(row.get('ST', '')),
                           CNTYNAME=safe_str(row.get('CNTYNAME', '')),
                           CBW=safe_str(row.get('CBW', '')),
                           FIPS_NHL=safe_str(row.get('FIPS_NHL', '')),
                           PRECIP=safe_str(row.get('PRECIP', '')),
                           MEANPRECIP=safe_str(row.get('MEANPRECIP', '')),
                           LndRvrSeg=safe_str(row.get('LndRvrSeg', '')),
                           Acres=safe_str(row.get('Acres', '')),
                           HGMR=safe_str(row.get('HGMR', '')),
                           index_righ=safe_str(row.get('index_righ', '')),
                           RiverSegN=safe_str(row.get('RiverSegN', '')),
                           LndRvrSegN=safe_str(row.get('LndRvrSegN', '')),
                           x_riverSeg=safe_str(row.get('x_riverSeg', '')),
                           y_riverSeg=safe_str(row.get('y_riverSeg', '')),
                           x_county=safe_str(row.get('x_county', '')),
                           y_county=safe_str(row.get('y_county', '')),
                           x_LRseg=safe_str(row.get('x_LRseg', '')),
                           y_LRseg=safe_str(row.get('y_LRseg', '')),
                           geometry=safe_str(row.get('geometry', ''))
        )

        # Sector-specific ACCEPT processes for N & P (no water/sediment)
        for sector in ("agricultural", "developed"):
            for operand in ("nitrogen", "phosphorus"):
                ET.SubElement(tr, 'TransformationProcess',
                              name=f"accept {sector} {operand}",
                              status="true",
                              varDomain="real",
                              inputOperand="",
                              inputOperandWeight="",
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
                          varDomain="real",
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
                      autonomous="true",
                      initCond="0,0")

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
                      autonomous="true",
                      initCond="0,0")

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
                          varDomain="real",
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
                              varDomain="real",
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
                          varDomain="real",
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