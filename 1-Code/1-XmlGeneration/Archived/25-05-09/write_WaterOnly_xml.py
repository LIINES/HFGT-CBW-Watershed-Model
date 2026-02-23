import xml.etree.ElementTree as ET
import xml.dom.minidom
def writeWaterOnlyXMLfromGDF(gdf_segments, gdf_outlet_points, gdf_outlet_lines, gdf_outlet_lines_estuary, gdf_estuary,
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

    # Add Operands
    ET.SubElement(root, 'Operand', operandName="water", operandType="matter")

    # Track created names to avoid duplicates
    created_transformation_resources = set()
    created_independent_buffers = set()
    created_transportation_resources = set()

    # Create TransformationResources only for segments with an outlet
    for _, row in gdf_segments.iterrows():
        resource_name = f"Land Segment {row['LndRvrSegN']}"
        if resource_name in created_transformation_resources:
            continue

        # Skip if there is no outlet for this segment
        matching_outlet_points = gdf_outlet_points[gdf_outlet_points['RiverSeg'] == row['RiverSegN']]
        if matching_outlet_points.empty:
            print(f"Skipping Land Segment {row['LndRvrSegN']} (no outlet point)")
            continue

        created_transformation_resources.add(resource_name)
        tr = ET.SubElement(root, 'TransformationResource',
                           transformationResourceName=resource_name,
                           gpsX=str(row['x_riverSeg']),
                           gpsY=str(row['y_riverSeg']),
                           decisionMaker="",
                           autonomous="true",
                           riverSeg=str(row['RiverSegN']),
                           county=str(row['FIPS_NHL']))

        ET.SubElement(tr, 'TransformationProcess',
                      name="accept water",
                      status="true",
                      inputOperand="",
                      inputOperandWeight="0",
                      outputOperand="water",
                      outputOperandWeight="1",
                      precip=str(row['PRECIP']),
                      meanPrecip=str(row['MEANPRECIP']))

        outlet_point = matching_outlet_points.iloc[0]
        ET.SubElement(tr, 'TransportationProcess',
                      name="transport",
                      status="true",
                      origin=resource_name,
                      destination=f"Outlet {outlet_point['RiverSeg']}",
                      ref="water",
                      inputOperand="water",
                      inputOperandWeight="1",
                      outputOperand="water",
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

        ET.SubElement(tr, 'TransportationProcess',
                      name=f"transport",
                      status="true",
                      origin=f"Outlet {row['from']}",
                      destination=f"Outlet {row['to']}",
                      ref="water",
                      inputOperand="water",
                      inputOperandWeight="1",
                      outputOperand="water",
                      outputOperandWeight="1")

    # Add TransportationResources (outlet to estuary)
    # First connect Outlet A to Outlet B (e.g., Outlet _0001 → Outlet _0000)
    # Then connect Outlet B to the estuary (e.g., Outlet _0000 → Estuary)
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

            ET.SubElement(tr, 'TransportationProcess',
                          name=f"transport",
                          status="true",
                          origin=f"Outlet {row['from']}",
                          destination=f"Outlet {row['to']}",
                          ref="water",
                          inputOperand="water",
                          inputOperandWeight="1",
                          outputOperand="water",
                          outputOperandWeight="1")

        # # Connect estuary-adjacent outlet to estuary
        # resource_name_2 = f"River Segment {row['to']} to {estuary_name}"
        # if resource_name_2 not in created_transportation_resources and row['to'] not in assigned_to_estuary:
        #     created_transportation_resources.add(resource_name_2)
        #     assigned_to_estuary.add(row['to'])
        #
        #     tr = ET.SubElement(root, 'TransportationResource',
        #                        transportationResourceName=resource_name_2,
        #                        decisionMaker="",
        #                        autonomous="true")
        #
        #     ET.SubElement(tr, 'TransportationProcess',
        #                   name=f"transport",
        #                   status="true",
        #                   origin=f"Outlet {row['to']}",
        #                   destination=estuary_name,
        #                   ref="water",
        #                   inputOperand="water",
        #                   inputOperandWeight="1",
        #                   outputOperand="water",
        #                   outputOperandWeight="1")
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

        ET.SubElement(tr, 'TransportationProcess',
                      name=f"transport",
                      status="true",
                      origin=from_outlet,
                      destination=estuary_name,
                      ref="water",
                      inputOperand="water",
                      inputOperandWeight="1",
                      outputOperand="water",
                      outputOperandWeight="1")

    # Pretty-print and write
    xml_str = ET.tostring(root, encoding='utf-8')
    parsed = xml.dom.minidom.parseString(xml_str)
    pretty_str = parsed.toprettyxml(indent="    ")

    with open(outputFile, 'w', encoding='utf-8') as f:
        f.write(pretty_str)

    print("XML file has been created successfully.")