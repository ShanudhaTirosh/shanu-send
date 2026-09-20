import type { Device } from "../../types";
import { ShanuConnectPanel } from "../shanuconnect/ShanuConnectPanel";

interface PhoneControlPanelProps {
  selectedDevice: Device | null;
  devices?: Device[];
}

export function PhoneControlPanel({ selectedDevice, devices = [] }: PhoneControlPanelProps) {
  return <ShanuConnectPanel selectedDevice={selectedDevice} devices={devices} />;
}
