Washing Machine FSM – Digital System Design
A digital washing machine controller implemented in VHDL using a modular Finite State Machine (FSM) architecture. The project simulates the control logic of an automatic and manual washing machine, including washing, spinning, drying, timer management, door safety, and cleanliness evaluation.

Developed for FPGA implementation using Xilinx Vivado and the Nexys A7-100T development board.

Project Overview
The system is designed with a modular architecture, separating the main controller into independent functional components. This improves code organization, readability, and maintainability.

Key Features
Automatic Mode: Selects washing programs (Quick, Normal, Heavy) with adjustable laundry weight.
Manual Mode: Allows users to configure water level, temperature, washing duration, and spinning options.
Washing and Spinning Control: Manages washing and spinning cycles using countdown timers.
Drying Function: Supports optional drying with selectable duration.
Button Debouncing: Filters mechanical button signals to prevent unintended multiple inputs.
Door Safety Mechanism: Detects an open door before or during operation and provides error handling.
Pause and Resume: Supports pausing and resuming operation.
Cleanliness Evaluation: Calculates a cleanliness score and provides a re-wash suggestion.
Display Interface: Uses an 8-digit seven-segment display and 16 LEDs to show system status and operation progress.
Hardware & Development Tools
Category	Technology
Hardware Description Language	VHDL
FPGA Development Tool	Xilinx Vivado
FPGA Board	Nexys A7-100T
Clock Frequency	100 MHz
Display	8-digit Seven-Segment Display
Inputs	Push Buttons and 16 Slide Switches
Outputs	16 LEDs, Seven-Segment Display
Project Architecture
The design consists of six VHDL source files organized into independent modules.

File	Responsibility
Washing_Machine_FSM.vhd	Top-level entity connecting all functional modules
WM_pkg.vhd	Shared package containing FSM states, display constants, and calculation functions
WM_Debouncer.vhd	Filters mechanical button signals and generates clean input pulses
WM_Timer.vhd	Generates timing signals for countdown and display blinking
WM_FSM_Core.vhd	Implements the main FSM, state transitions, timers, and safety logic
WM_Display.vhd	Controls seven-segment display multiplexing and LED indicators
Washing_Machine_FSM_v3.xdc	FPGA pin assignments and clock constraints for Nexys A7-100T
Module Interaction
The top-level controller integrates the four functional modules:

WM_Debouncer: Processes four push-button inputs.
WM_Timer: Provides timing signals to the controller and display.
WM_FSM_Core: Manages washing machine operations and state transitions.
WM_Display: Converts system states and parameters into visual outputs.
WM_pkg provides shared definitions and calculation functions used across the design.

Input Configuration
Push Buttons
Button	Function
BTNC	Confirm / Yes
BTNL	Cancel / No / Back
BTNU	Skip countdown
BTNR	Hard Reset to Idle
Slide Switches
Switch	Function
SW15	Automatic (1) / Manual (0)
SW14–13	Automatic program selection
SW12–11	Laundry weight (Auto) / Washing time (Manual)
SW10–9	Water level
SW8–7	Water temperature
SW6	Re-wash threshold
SW5	Spin / Redo selection
SW4	Door status (1 = Closed)
SW3	Pause
SW2	Cleanliness and re-wash feature
SW1	Drying request
SW0	Drying duration (Short / Long)
Safety and Error Handling
The system implements two door-related error conditions:

E01 – Door Open Before Start: Prevents the washing process from starting when the door is open.
E02 – Door Open During Operation: Detects an open door during washing, spinning, or drying. The system saves the current operation state and timer information to support resuming after the door is closed.
Repository Structure
Washing_Machine_DigitalProject/
│
├── Washing_Machine_FSM.vhd
├── WM_pkg.vhd
├── WM_Debouncer.vhd
├── WM_Timer.vhd
├── WM_FSM_Core.vhd
├── WM_Display.vhd
└── Washing_Machine_FSM_v3.xdc
Getting Started
Requirements
Xilinx Vivado Design Suite
Nexys A7-100T FPGA board (for hardware implementation)
Setup Instructions
Open Xilinx Vivado and create a new RTL project.
Select the Nexys A7-100T FPGA device.
Add all six .vhd files as Design Sources.
Add Washing_Machine_FSM_v3.xdc as a Constraints file.
Set Washing_Machine_FSM as the Top Module.
Run Synthesis and Implementation.
Generate the Bitstream and program the FPGA board.
Learning Outcomes
This project demonstrates practical knowledge and application of:

Finite State Machine (FSM) design and state transition management.
Modular VHDL architecture and component integration.
Digital timing and countdown control.
Button debouncing and input signal processing.
Seven-segment display multiplexing.
FPGA pin assignment and timing constraints.
Hardware-oriented problem solving and system-level design.
Project Type: Digital System Design / FPGA
Language: VHDL
Development Environment: Xilinx Vivado
Target Board: Nexys A7-100T
