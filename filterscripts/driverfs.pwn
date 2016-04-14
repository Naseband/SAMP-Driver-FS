/* -----------------------------------------------------------------------------

Smooth NPC Drivers - Have some Singleplayer-like NPCs on your server! - by NaS & AIped (c) 2013-2016

Version: 1.2.1

This is the FS-version of our NPC Drivers Script.
To find bugs and improve its features we decided to release this compact version for testing and experimenting purposes.

Please post any suggestions or buggy encounters to our thread in the official SA-MP Forums (http://forum.sa-mp.com/showthread.php?t=587634). Thanks!

Note: The steep-hills-glitch (vehicles snapping around while driving up/down) is not possible to fix script-wise. This is probably caused by the "smooth" but unprecise movement of NPCs.

---------------

> Credits

	AIped - Initiator of the 2013 version, help, ideas, scripting, ...
	Gamer_Z - RouteConnector Plugin, QuaternionStuff Plugin and great help with some math-problems
	OrMisicL & ZiGGi - FCNPC Plugin
	Incognito - Streamer Plugin
	Pottus and other developers of ColAndreas

Feel free to use and modify as you wish, but don't re-release this without our permission!

// -----------------------------------------------------------------------------

Latest Changenotes:
[v1.2.1]

- Support for newest (1.0.4) FCNPC version
- Added Cops (count as civilains)
   Cops turn on the sirens sometimes to annoy their surroundings
- Added Skin Arrays for different types (Civ, Cops, Taxis)
- There is a very rough time measurement now when you choose your destination
- Fixed stop'n'go (Using math instead of crappy distance guesses)

[v1.2]

- General performance improvements
- Using ColAndreas for more precise rotations
. Using Streamer Plugin for Areas
- Manually fixed hundreds of nodes
- Reduction of path length (-> Less memory usage)
- Streaming NPC-Movements (npcs will move very roughly (skip every 3 nodes) if no players are around -> saving quite a lot run-time calculations)
- NPCs brake when someone (another npc) is in front of them

[v1.1]

- Improved random start- and destination node calculations (added RandomNodes array), also improves NPC spreading around the world
- Shortened paths on recalculations (performance improvement)
- Improved speed calculations, speed changes over time by steepness and turning radiuses
- Brakes when near to destination


*///----------------------------------------------------------------------------

// -----------------------------------------------------------------------------


#include <a_samp>
#undef MAX_PLAYERS
#define MAX_PLAYERS				(1000)
#include <FCNPC>
#undef MAX_NODES
#include <RouteConnector>
#include <ColAndreas>
#include <QuaternionStuff>
#include <streamer>

// ----------------------------------------------------------------------------- CONFIG

#define NPC_NAMES           	"DRIVER%003d" // %d will be replaced by the Drivers's ID (not NPC ID!)

#define DEBUG_PRINTS			(false) // Prints calculation times and warnings
#define INFO_PRINTS				(true) // Prints Driver Info every X seconds
#define INFO_DELAY				(300) // seconds
#define MAP_ZONES				(false) // Creates gang zones for every driver as replacement for a map marker (all npcs are always visible in ESC->Map)

#define DRIVER_AMOUNT			(250)  	// TOTAL NPC COUNT - Different driver types are part of the overall driver amount
#define DRIVER_TAXIS			(70)

#define MAX_NODE_DIST			(17.0)
#define MIN_NODE_DIST			(3.5)
#define SIDE_DIST				(2.075)

#define MIN_SPEED				(0.65)
#define MAX_SPEED				(1.85)

#define JAM_DIST                (13.5) // Distance between 2 Drivers to make them slow down
#define JAM_ANGLE               (25) // INT! Max angle distance between 2 Drivers to make them slow down

#define MAX_PATH_LEN    		(2000)

#define TAXI_RANGE				(35.0) // range to valid nodes (player)
#define TAXI_COOLDOWN			(60) // seconds
#define TAXI_TIMEOUT			(40) // seconds

#define DRIVER_RANGE_ROT_ONLY	(300.0) // If no player is in this range, the npc will move very roughly, else do only rotations
#define DRIVER_RANGE_SMOOTH		(190.0) // If any player is in this range, an npc will do smooth movement and drive more carefully

#define ROUTE_MIN_DIST			(650.0) // Minimum distance for random routes

#define DRIVERS_ROUTE_ID		(10000) // Starting routeid for path calculations - change if conflicts arise
#define DIALOG_ID				(10000) // Starting dialogid for dialogs - change if conflicts arise

// ----------------------------------------------------------------------------- INTERNAL CONFIG/DEFINES

#define DRIVER_TYPE_RANDOM		(0)
#define DRIVER_TYPE_TAXI		(1)

#define DRIVER_STATE_NONE		(0)
#define DRIVER_STATE_DRIVE		(1)
#define DRIVER_STATE_PAUSE		(2)

#define MAX_SMOOTH_PATH			(MAX_PATH_LEN + 1)
#define S_DIMENSIONS			(2)  // We only smooth x/y here

#define MAX_RANDOM_NODES		(3650)

#define TAXI_STATE_NONE			(0)
#define TAXI_STATE_DRIVE1		(1)
#define TAXI_STATE_WAIT1		(2)
#define TAXI_STATE_DRIVE2		(3)

#define ZONES_NUM				(60) // This is just for determining npc distances to each other via integers, lower value means bigger zones

#define DID_TAXI				(DIALOG_ID + 0)

#pragma dynamic					(64*1000) // Needs to be higher for longer paths/more npcs!

// -----------------------------------------------------------------------------

enum E_DRIVERS
{
	bool:nUsed,
	bool:nOnDuty,
	bool:nActive, // Active means a player is close (-> does all calculations)
	bool:nIsCop,
	nNPCID,
	nType,
	nState,
	nCurNode,
	nLastDest,
	Float:nDistance,
	Float:nSpeed,
	nVehicle,
	nVehicleModel,
	nPlayer,
	nLT, // Last Tick
	nCopStuffTick,
	nCalcFails,
	nStreamingAreaS,
	nStreamingAreaL,
	nZoneX,
	nZoneY
	
	#if MAP_ZONES == true
	, nGangZone
	#endif
};
new Drivers[DRIVER_AMOUNT][E_DRIVERS];

new Float:DriverPath[DRIVER_AMOUNT][MAX_PATH_LEN][3];
new DriverPathLen[DRIVER_AMOUNT];

new Float:VehicleZOffsets[] = // Contains normal 4wheel vehicles, including Quad, Police Cars and Police Rancher, no special vehicles
{
	1.0982/*(400)*/,0.7849/*(401)*/,0.8371/*(402)*/,-1000.0/*(403)*/,0.7416/*(404)*/,0.8802/*(405)*/,-1000.0/*(406)*/,-1000.0/*(407)*/,-1000.0/*(408)*/,0.7901/*(409)*/,
	0.6667/*(410)*/,-1000.0/*(411)*/,0.8450/*(412)*/,-1000.0/*(413)*/,-1000.0/*(414)*/,0.7754/*(415)*/,-1000.0/*(416)*/,-1000.0/*(417)*/,-1000.0/*(418)*/,0.8033/*(419)*/,
	0.7864/*(420)*/,0.8883/*(421)*/,0.9969/*(422)*/,-1000.0/*(423)*/,0.7843/*(424)*/,-1000.0/*(425)*/,0.7490/*(426)*/,-1000.0/*(427)*/,1.1306/*(428)*/,0.6862/*(429)*/,
	-1000.0/*(430)*/,-1000.0/*(431)*/,-1000.0/*(432)*/,-1000.0/*(433)*/,-1000.0/*(434)*/,-1000.0/*(435)*/,0.7756/*(436)*/,-1000.0/*(437)*/,1.0092/*(438)*/,0.9020/*(439)*/,
	1.1232/*(440)*/,-1000.0/*(441)*/,0.8379/*(442)*/,-1000.0/*(443)*/,-1000.0/*(444)*/,0.8806/*(445)*/,-1000.0/*(446)*/,-1000.0/*(447)*/,-1000.0/*(448)*/,-1000.0/*(449)*/,
	-1000.0/*(450)*/,-1000.0/*(451)*/,-1000.0/*(452)*/,-1000.0/*(453)*/,-1000.0/*(454)*/,-1000.0/*(455)*/,-1000.0/*(456)*/,-1000.0/*(457)*/,0.8842/*(458)*/,-1000.0/*(459)*/,
	-1000.0/*(460)*/,-1000.0/*(461)*/,-1000.0/*(462)*/,-1000.0/*(463)*/,-1000.0/*(464)*/,-1000.0/*(465)*/,0.7490/*(466)*/,0.7465/*(467)*/,-1000.0/*(468)*/,-1000.0/*(469)*/,
	-1000.0/*(470)*/,0.3005/*(471)*/,-1000.0/*(472)*/,-1000.0/*(473)*/,0.7364/*(474)*/,0.8077/*(475)*/,-1000.0/*(476)*/,-1000.0/*(477)*/,1.0010/*(478)*/,0.7994/*(479)*/,
	0.7799/*(480)*/,-1000.0/*(481)*/,1.1209/*(482)*/,-1000.0/*(483)*/,-1000.0/*(484)*/,-1000.0/*(485)*/,-1000.0/*(486)*/,-1000.0/*(487)*/,-1000.0/*(488)*/,1.1498/*(489)*/,
	-1000.0/*(490)*/,0.7619/*(491)*/,0.7875/*(492)*/,-1000.0/*(493)*/,-1000.0/*(494)*/,1.3588/*(495)*/,0.7226/*(496)*/,-1000.0/*(497)*/,1.0726/*(498)*/,0.9988/*(499)*/,
	1.1052/*(500)*/,-1000.0/*(501)*/,-1000.0/*(502)*/,-1000.0/*(503)*/,-1000.0/*(504)*/,1.1498/*(505)*/,0.7100/*(506)*/,0.8319/*(507)*/,1.3809/*(508)*/,-1000.0/*(509)*/,
	-1000.0/*(510)*/,-1000.0/*(511)*/,-1000.0/*(512)*/,-1000.0/*(513)*/,1.5913/*(514)*/,-1000.0/*(515)*/,0.8388/*(516)*/,0.8608/*(517)*/,0.6761/*(518)*/,-1000.0/*(519)*/,
	-1000.0/*(520)*/,-1000.0/*(521)*/,-1000.0/*(522)*/,-1000.0/*(523)*/,-1000.0/*(524)*/,-1000.0/*(525)*/,0.7724/*(526)*/,0.7214/*(527)*/,-1000.0/*(528)*/,0.6374/*(529)*/,
	-1000.0/*(530)*/,-1000.0/*(531)*/,-1000.0/*(532)*/,0.7152/*(533)*/,0.7315/*(534)*/,0.7702/*(535)*/,0.7437/*(536)*/,-1000.0/*(537)*/,-1000.0/*(538)*/,-1000.0/*(539)*/,
	0.8672/*(540)*/,-1000.0/*(541)*/,0.7501/*(542)*/,0.8309/*(543)*/,-1000.0/*(544)*/,0.8169/*(545)*/,0.7293/*(546)*/,0.7404/*(547)*/,-1000.0/*(548)*/,0.7048/*(549)*/,
	0.8274/*(550)*/,0.8066/*(551)*/,-1000.0/*(552)*/,-1000.0/*(553)*/,1.0894/*(554)*/,0.6901/*(555)*/,-1000.0/*(556)*/,-1000.0/*(557)*/,0.6349/*(558)*/,0.6622/*(559)*/,
	0.7105/*(560)*/,0.8190/*(561)*/,0.6632/*(562)*/,-1000.0/*(563)*/,-1000.0/*(564)*/,0.6317/*(565)*/,0.7889/*(566)*/,0.8733/*(567)*/,0.8720/*(568)*/,-1000.0/*(569)*/,
	-1000.0/*(570)*/,-1000.0/*(571)*/,-1000.0/*(572)*/,-1000.0/*(573)*/,-1000.0/*(574)*/,0.6107/*(575)*/,0.6128/*(576)*/,-1000.0/*(577)*/,-1000.0/*(578)*/,0.9359/*(579)*/,
	0.8016/*(580)*/,-1000.0/*(581)*/,-1000.0/*(582)*/,-1000.0/*(583)*/,-1000.0/*(584)*/,0.5899/*(585)*/,-1000.0/*(586)*/,0.7336/*(587)*/,-1000.0/*(588)*/,0.6643/*(589)*/,
	-1000.0/*(590)*/,-1000.0/*(591)*/,-1000.0/*(592)*/,-1000.0/*(593)*/,-1000.0/*(594)*/,-1000.0/*(595)*/,0.7278/*(596)*/,0.7756/*(597)*/,0.7178/*(598)*/,1.1971/*(599)*/,
	0.7171/*(600)*/,-1000.0/*(601)*/,0.8129/*(602)*/,0.8440/*(603)*/,-1000.0/*(604)*/,-1000.0/*(605)*/,-1000.0/*(606)*/,-1000.0/*(607)*/,-1000.0/*(608)*/,1.0727/*(609)*/,
	-1000.0/*(610)*/,-1000.0/*(611)*/
};

new DriverSkins[] = // Skin IDs for citizens, not sorted - no specific/story skins
{
	10, 101, 12, 13, 136, 14, 142, 143, 15, 151, 156, 168, 169,
	17, 170, 180, 182, 183, 184, 263, 186, 185, 19, 216, 91, 206,
	21, 22, 210, 214, 215, 220, 221, 225, 226, 222, 223, 227, 231,
	228, 234, 76, 235, 236, 89, 88, 24, 218, 240, 25, 250, 261, 40,
	41, 35, 37, 38, 44, 69, 43, 46, 9, 93, 39, 48, 47, 229, 58, 59,
	60, 233, 72, 55, 94, 95, 98, 241, 242, 73, 83
};

new CopSkins[] = // Skin IDs for cops
{
	280, 281, 282, 283, 288, 306, 307, 310, 311
};

new TaxiSkins[] = // Skin IDs for taxi drivers - kind of randomly picked
{
	188, 20, 36, 262, 7, 56
};

new RandomNodes[MAX_RANDOM_NODES], RandomNodesNum = 0;

new RandomVehicleList[212], VehicleListNum = 0;

new Taxi[MAX_PLAYERS] = {-1, ...}; // -1 => no taxi called, everything else => driverid
new TaxiState[MAX_PLAYERS] = {TAXI_STATE_NONE};
new LastTaxiInteraction[MAX_PLAYERS];
new bool:InTaxiView[MAX_PLAYERS];

enum E_DESTINATIONS
{
	destName[24],
	Float:destX,
	Float:destY,
	Float:destZ
};
new gDestinationList[][E_DESTINATIONS] =
{
	{"Los Santos", 1643.2167, -2241.9209, 13.4900},
	{"San Fierro", -1424.2325, -291.3162, 14.1484},
	{"Las Venturas", 1682.3629, 1447.5713, 10.7722,},

	{"Grove Street (LS)", 2500.9397, -1669.3757, 13.3438},
	{"Skatepark (LS)", 1923.5677,-1403.0310,13.2974},
	{"Mount Chiliad (LS)",  -2250.8413,-1719.0470,480.0685},

	{"Jizzy's Club (SF)", -2625.6680, 1382.9760, 7.1820},
	{"Wang Cars (SF)", -1976.1716, 287.7719, 35.1719},

	{"Verdant Meadows (LV)", 399.0638, 2484.6252, 16.484375},

	{"Blueberry (LS)", 200.8919, -144.7279, 1.5859},
	{"Palomino Creek (LS)", 2266.0808, 27.1097, 26.1645},
	{"Bayside (SF/LV)", -2466.1084, 2234.2334, 4.5125},
	{"Angel Pine (SF/LS)", -2119.8252, -2492.1013, 30.6250},
	{"El Quebrados (LV)", -1516.0896, 2540.1277, 55.6875},
	{"Las Barrancas (LV)", -745.9706, 1565.6580, 26.9609},
    {"Las Payasadas (LV)", -170.1701, 2693.7996, 62.4128}
};
new dialogstr[430];

new MaxPathLen = 0;

new rescueid = 0; // Current ID to check in the RescueTimer (only checks few entries (50) each time it calls to prevent long loops)
new avgcalctimes[50] = {100, ...}, avgcalcidx;
new avgticks[50] = {200, ...}, avgtickidx;
new rescuetimer = -1;
#if INFO_PRINTS == true
new updtimer = -1;
#endif

new bool:Initialized = false;
new InitialCalculations = 0, InitialCalculationStart;

// -----------------------------------------------------------------------------

public OnFilterScriptInit()
{
	Drivers_Init();
}

public OnFilterScriptExit()
{
	Drivers_Exit(0);
}

public OnGameModeInit()
{
	Drivers_Init();
}

public OnGameModeExit()
{
	Drivers_Exit(0);
}

// -----------------------------------------------------------------------------

Drivers_Init()
{
	if(Initialized) return 1;

	FCNPC_SetUpdateRate(GetServerVarAsInt("incar_rate")*2);

	//CA_Init(); // You should uncomment this if you don't initialize ColAndreas before this FS gets loaded!

	for(new i = 0; i < sizeof(gDestinationList); i ++) format(dialogstr, sizeof(dialogstr), "%s{999999}%s\n", dialogstr, gDestinationList[i][destName]);

	if(rescuetimer != -1) KillTimer(rescuetimer);
	rescuetimer = SetTimer("RescueTimer", 500, 1);
	
	#if INFO_PRINTS == true
	if(updtimer != -1) KillTimer(updtimer);
	updtimer = SetTimer("PrintDriverUpdate", INFO_DELAY*1000, 1);
	#endif
	
	// ---------------- LOAD FILES
	
	new File:FIn = fopen("ValidGPSNodes.txt", io_read), tmp[10];
	
	if(FIn)
	{
	    while(fread(FIn, tmp) && RandomNodesNum < MAX_RANDOM_NODES)
	    {
			new nodeid = strval(tmp);
			
			if(nodeid >= 0 && nodeid < MAX_NODES && NodeExists(nodeid))
			{
			    RandomNodes[RandomNodesNum] = nodeid;
			    RandomNodesNum ++;
			}
	    }
	    fclose(FIn);
	}
	else
	{
	    print("[DRIVERS] Error: No Random Nodes found!");
	    return 1;
	}

	// ---------------- CONNECT NPCS & stuff

	for(new i = 0; i <= 211; i ++)
	{
	    if(VehicleZOffsets[i] < -950.0 || i == 20 || i == 38) continue;

		RandomVehicleList[VehicleListNum] = i+400;

		VehicleListNum ++;
	}

    for(new i = 0; i < MAX_PLAYERS; i ++)
	{
	    if(IsPlayerConnected(i) && !IsPlayerNPC(i) && InTaxiView[i]) SetCameraBehindPlayer(i);

	    Taxi[i] = -1;
	    LastTaxiInteraction[i] = GetTickCount() - TAXI_COOLDOWN*1000;
	}

	new maxnpc = GetServerVarAsInt("maxnpc"), othernpcs = 0;

	for(new i = 0; i < MAX_PLAYERS; i ++) if(IsPlayerNPC(i)) othernpcs ++;
	
	Initialized = true;
	InitialCalculationStart = GetTickCount();

    for(new i = 0; i < DRIVER_AMOUNT; i ++) Drivers[i][nNPCID] = -1;

    new npcname[MAX_PLAYER_NAME];

	for(new i = 0; i < DRIVER_AMOUNT; i ++)
	{
		if(i >= maxnpc - othernpcs)
		{
		    printf("[DRIVERS] Error: maxnpc exceeded, current limit for this script: %d.", maxnpc-othernpcs);
		    for(new j = i; j < DRIVER_AMOUNT; j ++) Drivers[j][nUsed] = false;

			break;
		}

		new startnode = GetRandomNode(), endnode = GetRandomNode();

		while(GetDistanceBetweenNodes(startnode, endnode) < ROUTE_MIN_DIST)
		{
		    endnode = GetRandomNode();
		}

		new Float:X, Float:Y, Float:Z, Float:mZ;
		GetNodePos(startnode, X, Y, Z);
		CA_FindZ_For2DCoord(X, Y, mZ);

		if(mZ - Z < 2.0) Z = mZ;

		new vmodel, colors[2], skinid;

		if(i < DRIVER_TAXIS)
		{
			Drivers[i][nType] = DRIVER_TYPE_TAXI;
			Drivers[i][nIsCop] = false;
			
			vmodel = (random(2) == 0 ? 420 : 438);
			skinid = TaxiSkins[random(sizeof(TaxiSkins))];
			colors = {-1, -1};
		}
		else
		{
			Drivers[i][nType] = DRIVER_TYPE_RANDOM;
			
			vmodel = RandomVehicleList[random(VehicleListNum)];
			
			switch(vmodel) // Decide whether that driver is a cop or not by vehicle model (makes them a bit rare on purpose)
			{
			    case 596, 597, 598, 599:
			    {
			        Drivers[i][nIsCop] = true;
			        
			        skinid = CopSkins[random(sizeof(CopSkins))];
			        colors = {-1, -1};
			    }
			    default:
			    {
			        Drivers[i][nIsCop] = false;
			        
			        skinid = DriverSkins[random(sizeof(DriverSkins))];
			        colors[0] = random(127), colors[1] = random(127);
			    }
			}
		}

		Drivers[i][nVehicle] = CreateVehicle(vmodel, X, Y, Z + 100000.0, 0.0, colors[0], colors[1], 128); // Spawn somewhere where noone ever will get! This prevents FCNPC's spawn flickering (vehicles showing up at spawn coords between movements for < 1ms (annoying when driving into them just then!))

		format(npcname, MAX_PLAYER_NAME, NPC_NAMES, i);

		Drivers[i][nNPCID] = FCNPC_Create(npcname);
		
		if(!IsPlayerNPC(Drivers[i][nNPCID]))
		{
		    printf("[DRIVERS] Error: Failed creating NPC (Driver ID %d). Aborted!", i);
			break;
		}
		
		FCNPC_Spawn(Drivers[i][nNPCID], skinid, X, Y, Z + VehicleZOffsets[vmodel - 400]);
		FCNPC_PutInVehicle(Drivers[i][nNPCID], Drivers[i][nVehicle], 0);
		FCNPC_SetPosition(Drivers[i][nNPCID], X, Y, Z + VehicleZOffsets[vmodel - 400]);
		FCNPC_SetInvulnerable(Drivers[i][nNPCID], true);

		Drivers[i][nOnDuty] = false;
		Drivers[i][nPlayer] = -1;
		Drivers[i][nCurNode] = 0;
		Drivers[i][nState] = DRIVER_STATE_NONE;
		Drivers[i][nVehicleModel] = vmodel;
		Drivers[i][nUsed] = true;
		Drivers[i][nLT] = GetTickCount();
		#if MAP_ZONES == true
		Drivers[i][nGangZone] = -1;
		#endif
		
		Drivers[i][nStreamingAreaS] = CreateDynamicSphere(0.0, 0.0, 0.0, DRIVER_RANGE_SMOOTH, -1, -1, -1);
		Drivers[i][nStreamingAreaL] = CreateDynamicSphere(0.0, 0.0, 0.0, DRIVER_RANGE_ROT_ONLY, -1, -1, -1);
		Streamer_SetIntData(STREAMER_TYPE_AREA, Drivers[i][nStreamingAreaS], E_STREAMER_EXTRA_ID, -1);
		Streamer_SetIntData(STREAMER_TYPE_AREA, Drivers[i][nStreamingAreaL], E_STREAMER_EXTRA_ID, -1);
		AttachDynamicAreaToPlayer(Drivers[i][nStreamingAreaS], Drivers[i][nNPCID]);
		AttachDynamicAreaToPlayer(Drivers[i][nStreamingAreaL], Drivers[i][nNPCID]);
		
		pubCalculatePath(i, startnode, endnode);
	}

	printf("\n\n[DRIVERS] Total Drivers: %d, Random Drivers: %d, Taxi Drivers: %d\n          maxnpc: %d, Other NPCs: %d\n          Number of random nodes: %d\n\n", DRIVER_AMOUNT, (DRIVER_AMOUNT - DRIVER_TAXIS), DRIVER_TAXIS, maxnpc, othernpcs, RandomNodesNum);
	
	return 1;
}

forward Drivers_Exit(force);
public Drivers_Exit(force)
{
	if(!Initialized && force == 0) return 1;
	
	for(new i = 0; i < MAX_PLAYERS; i ++)
	{
	    if(IsPlayerConnected(i) && !IsPlayerNPC(i) && InTaxiView[i]) SetCameraBehindPlayer(i);
	    
	    Taxi[i] = -1;
	}
	
	for(new i = 0; i < DRIVER_AMOUNT; i ++)
	{
	    if(!Drivers[i][nUsed]) continue;
	    
	    Drivers[i][nUsed] = false;
	    
        if(GetVehicleModel(Drivers[i][nVehicle]) >= 400) DestroyVehicle(Drivers[i][nVehicle]);
        
        if(IsPlayerNPC(Drivers[i][nNPCID])) FCNPC_Destroy(Drivers[i][nNPCID]);
        
        Drivers[i][nNPCID] = -1;
        Drivers[i][nVehicle] = -1;
	}
	
	if(rescuetimer != -1) KillTimer(rescuetimer);
	rescuetimer = -1;
	
	#if INFO_PRINTS == true
	if(updtimer != -1) KillTimer(updtimer);
	updtimer = -1;
	#endif
	
	Initialized = false;
	
	if(force != 0) SendRconCommand("unloadfs NPCs_FS");
	
	return 1;
}


// -----------------------------------------------------------------------------

public OnPlayerConnect(playerid)
{
	if(!IsPlayerNPC(playerid)) LastTaxiInteraction[playerid] = GetTickCount() - TAXI_COOLDOWN*1000;
}

public OnPlayerCommandText(playerid, cmdtext[])
{
	if(!Initialized) return 0;

	if(IsPlayerAdmin(playerid))
	{
	    new cmd[128], idx;
		cmd = strtok(cmdtext, idx);
	
		if(strcmp(cmd, "/DriverFSExit", true) == 0) // Exits the script, should be used instead of unloadfs (unloadfs crashes the server) - unloads the FS after 5 seconds
		{
			Initialized = false;
			SetTimerEx("Drivers_Exit", 5000, 0, "d", 1);
		    return 1;
		}

		if(strcmp(cmd, "/ds", true) == 0) // /ds [id] [seat] to sit into a driver car
		{
		    cmd = strtok(cmdtext, idx);
		    new slot;
		    if(strlen(cmd) < 1 || strval(cmd) < 0 || strval(cmd) >= DRIVER_AMOUNT) slot = 0;
			else slot = strval(cmd);

			new seat;

			cmd = strtok(cmdtext, idx);
			if(strval(cmd) == 0) seat = 1;
			else seat = strval(cmd);

		    PutPlayerInVehicle(playerid, Drivers[slot][nVehicle], seat < 0 ? 1 : seat);
			return 1;
		}

		if(strcmp(cmdtext, "/dinfo", true) == 0)
		{
		    PrintDriverUpdate();
		    return 1;
		}
	}
	
	if(strcmp(cmdtext, "/taxi", true) == 0)
	{
	    if(Taxi[playerid] != -1) return SendClientMessage(playerid, -1, "[Taxi Service]: {990000}Sorry Sir, it seems like you have already ordered a taxi."), 1;
	    
	    if(GetTickCount() - LastTaxiInteraction[playerid] < TAXI_COOLDOWN*1000) return SendClientMessage(playerid, -1, "[Taxi Service]: {990000}Sorry Sir, we don't have any available cabs right now."), 1;

		new taxi = -1, Float:tdist = 1500.0, Float:X, Float:Y, Float:Z, destnode = -1;
		GetPlayerPos(playerid, X, Y, Z);
		
		destnode = NearestNodeFromPoint(X, Y, Z, TAXI_RANGE);
	    if(IsNodeInPathFinder(destnode) < 1) destnode = NearestNodeFromPoint(X, Y, Z, TAXI_RANGE, destnode);
	    if(IsNodeInPathFinder(destnode) < 1) return SendClientMessage(playerid, -1, "[Taxi Service]: {990000}Sorry Sir, we don't have your location on our GPS."), 1;
		
		for(new i = 0; i < DRIVER_TAXIS; i ++)
		{
		    if(!Drivers[i][nUsed] || Drivers[i][nOnDuty] || !IsPlayerNPC(Drivers[i][nNPCID])) continue;
		    
		    if(Drivers[i][nState] != DRIVER_STATE_DRIVE) continue;
		    
		    new Float:dist = GetPlayerDistanceFromPoint(Drivers[i][nNPCID], X, Y, Z);
		    
		    if(dist < tdist)
		    {
		        taxi = i;
		        tdist = dist;
		    }
		}

	    if(taxi == -1) return SendClientMessage(playerid, -1, "[Taxi Service]: {990000}Sorry Sir, we don't have an available cab near you."), 1;

	    new startnode = -1, npcid = Drivers[taxi][nNPCID];

		FCNPC_GetPosition(npcid, X, Y, Z);
    	startnode = NearestNodeFromPoint(X, Y, Z, 100.0);
    	if(IsNodeInPathFinder(startnode) < 1) startnode = NearestNodeFromPoint(X, Y, Z, 100.0, startnode);
		if(IsNodeInPathFinder(startnode) < 1) return SendClientMessage(playerid, -1, "[Taxi Service]: {990000}Sorry Sir, we don't have an available cab near you."), 1;

		Drivers[taxi][nState] = DRIVER_STATE_NONE;
		if(FCNPC_IsMoving(npcid)) FCNPC_Stop(npcid);
		
		Drivers[taxi][nOnDuty] = true;
		Drivers[taxi][nPlayer] = playerid;

		if(tdist < TAXI_RANGE)
		{
			TaxiState[playerid] = TAXI_STATE_WAIT1;
			SetVehicleParamsForPlayer(Drivers[taxi][nVehicle], playerid, 1, 0);
			Drivers[taxi][nLastDest] = startnode;
			
            SendClientMessage(playerid, -1, "[Taxi Service]: {009900}Get in. We got a driver right around the corner!");
		}
		else
		{
		    pubCalculatePath(taxi, startnode, destnode);
		    TaxiState[playerid] = TAXI_STATE_DRIVE1;
		    
		    if(tdist < 250.0) SendClientMessage(playerid, -1, "[Taxi Service]: {009900}Stay where you are. A driver is on his way!");
			else if(tdist < 1000.0) SendClientMessage(playerid, -1, "[Taxi Service]: {DD9900}Please be patient, our driver may need some time to approach your location.");
			else SendClientMessage(playerid, -1, "[Taxi Service]: {DD5500}We don't have a taxi close to you. Please wait a few minutes.");
		}
		
		Taxi[playerid] = taxi;

	    return 1;
	}
	
	return 0;
}

public OnPlayerStateChange(playerid, newstate, oldstate)
{
	if(IsPlayerNPC(playerid)) return 1;
	
	if(!Initialized) return 1;
	
	if(newstate == PLAYER_STATE_PASSENGER)
	{
	    if(Taxi[playerid] >= 0 && Taxi[playerid] < DRIVER_TAXIS && TaxiState[playerid] == TAXI_STATE_WAIT1)
	    {
			if(IsPlayerNPC(Drivers[Taxi[playerid]][nNPCID]))
			{
			    if(GetPlayerVehicleID(playerid) == Drivers[Taxi[playerid]][nVehicle])
			    {
			        ShowPlayerDialog(playerid, DID_TAXI, DIALOG_STYLE_LIST, "Choose a destination", dialogstr, "Go", "Cancel");
			        SetVehicleParamsEx(Drivers[Taxi[playerid]][nVehicle], 1, 0, 0, 0, 0, 0, 0); 
			        
			        new Float:cX, Float:cY, Float:cZ, Float:A, Float:tX, Float:tY;
			        FCNPC_GetPosition(Drivers[Taxi[playerid]][nNPCID], cX, cY, cZ);
			        A = FCNPC_GetAngle(Drivers[Taxi[playerid]][nNPCID]);
			        
			        tX = cX;
					tY = cY;
			        if(GetVehicleModel(Drivers[Taxi[playerid]][nVehicle]) == 420)
			        {
				        GetXYInFrontOfPoint(cX, cY, A+180.0, cX, cY, 1.1);
				        GetXYInFrontOfPoint(cX, cY, A+90.0, cX, cY, 0.15);
				        cZ += 0.5;

				        GetXYInFrontOfPoint(tX, tY, A, tX, tY, 2.5);
			        }
			        else
			        {
			            GetXYInFrontOfPoint(cX, cY, A+180.0, cX, cY, 0.5);
				        GetXYInFrontOfPoint(cX, cY, A+90.0, cX, cY, 0.15);
				        cZ += 0.3;

				        GetXYInFrontOfPoint(tX, tY, A, tX, tY, 2.5);
			        }
			        SetPlayerCameraPos(playerid, cX, cY, cZ);
			        SetPlayerCameraLookAt(playerid, tX, tY, cZ-0.5);
			        
			        InTaxiView[playerid] = true;
			        
			        return 1;
			    }
		    }
		}
	}
	
	if(oldstate == PLAYER_STATE_PASSENGER)
	{
	    if(Taxi[playerid] >= 0 && Taxi[playerid] < DRIVER_TAXIS && TaxiState[playerid] == TAXI_STATE_DRIVE2)
	    {
	        SetTimerEx("ResetTaxi", 5000, 0, "dd", Taxi[playerid], 3000);
	    }
	}
	
	return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
    if(!Initialized) return 1;
    
	if(dialogid == DID_TAXI)
	{
	    if(Taxi[playerid] == -1 || TaxiState[playerid] != TAXI_STATE_WAIT1) return 1;
	    
	    if(response)
	    {
		    new destnode = NearestNodeFromPoint(gDestinationList[listitem][destX], gDestinationList[listitem][destY], gDestinationList[listitem][destZ], 100.0);

		    if(IsNodeInPathFinder(destnode) < 1)
			{
				ShowPlayerDialog(playerid, DID_TAXI, DIALOG_STYLE_LIST, "Choose a destination", dialogstr, "Go", "Cancel");
			    return SendClientMessage(playerid, -1, "[Taxi Service]: {990000}Weird. I can't find that spot on my map!"), 1;
			}
		    
			if(GetDistanceBetweenNodes(NearestPlayerNode(playerid), destnode) < 100.0)
			{
			    ShowPlayerDialog(playerid, DID_TAXI, DIALOG_STYLE_LIST, "Choose a destination", dialogstr, "Go", "Cancel");
			    return SendClientMessage(playerid, -1, "[Taxi Service]: {990000}Sorry, but this is not worth the petrol."), 1;
			}

		    Drivers[Taxi[playerid]][nState] = DRIVER_STATE_NONE;
			if(FCNPC_IsMoving(Drivers[Taxi[playerid]][nNPCID])) FCNPC_Stop(Drivers[Taxi[playerid]][nNPCID]);

			SetTimerEx("pubCalculatePath", 1000 + random(1000), 0, "ddd", Taxi[playerid], Drivers[Taxi[playerid]][nLastDest], destnode);

		    TaxiState[playerid] = TAXI_STATE_DRIVE2;

		    SetVehicleParamsEx(Drivers[Taxi[playerid]][nVehicle], 1, 0, 0, 0, 0, 0, 0);

		    SetCameraBehindPlayer(playerid);
		    InTaxiView[playerid] = false;
		    
		    LastTaxiInteraction[playerid] = GetTickCount();
	    }
	    else
	    {
	        SetCameraBehindPlayer(playerid);
	        InTaxiView[playerid] = false;
	        
	        ResetTaxi(Taxi[playerid], 5000);
	    }
	}
	return 1;
}

public OnPlayerEnterDynamicArea(playerid, areaid)
{
	return 1;
}

public OnPlayerLeaveDynamicArea(playerid, areaid)
{
	return 1;
}

// -----------------------------------------------------------------------------

forward pubCalculatePath(driverid, startnode, endnode);
public pubCalculatePath(driverid, startnode, endnode)
{
    if(!Initialized) return 1;
    
	if(driverid < 0 || driverid >= DRIVER_AMOUNT) return 1;
	
	if(!Drivers[driverid][nUsed]) return 1;
	
	if(Drivers[driverid][nState] != DRIVER_STATE_NONE) return 1;
	
	Drivers[driverid][nLT] = GetTickCount();
	
    CalculatePath(startnode, endnode, DRIVERS_ROUTE_ID + driverid, false, _, true);
    
    Drivers[driverid][nLastDest] = endnode;
    
	return 1;
}

forward pub_RemovePlayerFromVehicle(playerid);
public pub_RemovePlayerFromVehicle(playerid)
{
    RemovePlayerFromVehicle(playerid);
	return 1;
}

forward ResetTaxi(driverid, calcdelay);
public ResetTaxi(driverid, calcdelay)
{
    if(!Initialized) return 1;
    
	if(driverid < 0 || driverid >= DRIVER_TAXIS) return 1;
	
	if(!Drivers[driverid][nUsed] || !Drivers[driverid][nOnDuty] || Drivers[driverid][nType] != DRIVER_TYPE_TAXI) return 1;
	
	new playerid = Drivers[driverid][nPlayer];
	if(playerid >= 0 && playerid < MAX_PLAYERS)
	{
		TaxiState[playerid] = TAXI_STATE_NONE;
    	Taxi[playerid] = -1;
    	
    	LastTaxiInteraction[playerid] = GetTickCount();
    	
    	if(InTaxiView[playerid])
		{
			SetCameraBehindPlayer(playerid);
			HidePlayerDialog(playerid);
    		InTaxiView[playerid] = false;
    	}
    	
    	for(new i = 0; i < MAX_PLAYERS; i ++) if(!IsPlayerNPC(i) && GetPlayerVehicleID(i) == Drivers[driverid][nVehicle]) RemovePlayerFromVehicle(i);
	}
    
    if(GetPlayerVehicleID(playerid) == Drivers[driverid][nVehicle]) SetTimerEx("pub_RemovePlayerFromVehicle", 1000, 0, "d", playerid);
    SetVehicleParamsEx(Drivers[driverid][nVehicle], 1, 0, 0, 0, 0, 0, 0);
    
    if(FCNPC_IsMoving(Drivers[driverid][nNPCID])) FCNPC_Stop(Drivers[driverid][nNPCID]);

	Drivers[driverid][nState] = DRIVER_STATE_NONE;
	Drivers[driverid][nOnDuty] = false;
	Drivers[driverid][nLT] = GetTickCount();

	new Float:X, Float:Y, Float:Z;
    FCNPC_GetPosition(Drivers[driverid][nNPCID], X, Y, Z);

    new startnode = NearestNodeFromPoint(X, Y, Z);
    new endnode = -1;

    do
    {
		endnode = GetRandomNode();
    } while(GetDistanceBetweenNodes(startnode, endnode) < ROUTE_MIN_DIST);

	if(calcdelay > 0) SetTimerEx("pubCalculatePath", 2000, 0, "ddd", driverid, startnode, endnode);
	else pubCalculatePath(driverid, startnode, endnode);

	return 1;
}

forward RescueTimer();
public RescueTimer()
{
    if(!Initialized) return 1;
    
    if(avgtickidx >= sizeof(avgticks)) avgtickidx = 0;
    avgticks[avgtickidx] = GetServerTickRate();
    avgtickidx ++;
    
	for(new i = 0; i < 30; i ++)
	{
	    if(Drivers[rescueid][nUsed])
	    {
	        if(GetTickCount() - Drivers[rescueid][nLT] > TAXI_TIMEOUT*1000)
		  	{
		  	    if(FCNPC_IsMoving(Drivers[rescueid][nNPCID])) Drivers[rescueid][nLT] = GetTickCount();
		  	    else if(Drivers[rescueid][nType] == DRIVER_TYPE_TAXI && Drivers[rescueid][nOnDuty]) ResetTaxi(rescueid, 10000);
		  	    
			    #if DEBUG_BUBBLE == true
				new str[40];
				format(str, sizeof(str), "{888888}[%d]\n{DD0000}Timed out", rescueid);
				SetPlayerChatBubble(Drivers[rescueid][nNPCID], str, -1, 10.0, TAXI_TIMEOUT*1000);
				#endif
			}
	    }
	    rescueid ++;
	    
		if(rescueid >= DRIVER_AMOUNT) rescueid = 0;
	}
	return 1;
}

#if INFO_PRINTS == true
forward PrintDriverUpdate();
public PrintDriverUpdate()
#else
stock PrintDriverUpdate()
#endif
{
	new curtick = GetTickCount();
	
	new maxnpc = GetServerVarAsInt("maxnpc"), othernpcs = -DRIVER_AMOUNT, idlenpcs = 0;
	for(new i = 0; i < MAX_PLAYERS; i ++)
	{
		if(IsPlayerNPC(i)) othernpcs ++;
		
		if(i >= DRIVER_AMOUNT) continue;
		
		if(!Drivers[i][nUsed] || !IsPlayerNPC(Drivers[i][nNPCID])) continue;
		
		if(curtick - Drivers[i][nLT] > 60000) idlenpcs ++;
	}

	new Float:avgcalctime = 1.0*avgcalctimes[0];
	for(new i = 1; i < sizeof(avgcalctimes); i ++) avgcalctime += 1.0*avgcalctimes[i];
	avgcalctime = avgcalctime / (1.0*sizeof(avgcalctimes));
	
	new Float:avgtick = 1.0*avgticks[0];
	for(new i = 1; i < sizeof(avgticks); i ++) avgtick += 1.0*avgticks[i];
	avgtick = avgtick / (1.0*sizeof(avgticks));
	
	new rtms = curtick - InitialCalculationStart, rts, rtm, rth;
	
	rts = (rtms / 1000) % 60;
	rtm = (rtms / 60000) % 60;
	rth = rtms / 36000000;

	printf("\n[DRIVERS] Total Drivers: %d, Random Drivers: %d, Taxi Drivers: %d\n          maxnpc: %d, Other NPCs: %d, Idle NPCs: %d\n          Number of random nodes: %d\n          MaxPathLen: %d/%d, Uptime: %02d:%02d:%02d\n -  -  -  Avg. calc. time: %.02fms, Avg. Server Tick: %.02f\n", DRIVER_AMOUNT, (DRIVER_AMOUNT - DRIVER_TAXIS), DRIVER_TAXIS, maxnpc, othernpcs, idlenpcs, RandomNodesNum, MaxPathLen, MAX_PATH_LEN, rth, rtm, rts, avgcalctime, avgtick);
	return 1;
}

// -----------------------------------------------------------------------------

public GPS_WhenRouteIsCalculated(routeid,node_id_array[],amount_of_nodes,Float:distance,Float:Polygon[],Polygon_Size,Float:NodePosX[],Float:NodePosY[],Float:NodePosZ[])//Every processed Queue will be called here
{
    if(!Initialized) return 1;
    
    if(InitialCalculations < DRIVER_AMOUNT) InitialCalculations ++;
    
	new t = GetTickCount();
	
	if(routeid >= DRIVERS_ROUTE_ID && routeid < DRIVERS_ROUTE_ID + DRIVER_AMOUNT) // the routeid given comes from this script
	{
		new driverid = routeid - DRIVERS_ROUTE_ID;

		if(!Drivers[driverid][nUsed]) return 1;
		
		if(!IsPlayerNPC(Drivers[driverid][nNPCID])) return 1;
		
		if(Drivers[driverid][nState] != DRIVER_STATE_NONE) return 1;
		
		if(amount_of_nodes < 3)
		{
			#if DEBUG_PRINTS == true
		 	print("[DRIVERS] Error: Failed calculating path for Driver ID %d", driverid);
			#endif
			
			Drivers[driverid][nCalcFails] ++;
			return 1;
		}
		
		Drivers[driverid][nCalcFails] = 0;
		Drivers[driverid][nLT] = GetTickCount();
		
		new arrayid = 0, Float:newpath[MAX_SMOOTH_PATH][S_DIMENSIONS];

        DriverPath[driverid][0][0] = NodePosX[0];
		DriverPath[driverid][0][1] = NodePosY[0];
		DriverPath[driverid][0][2] = NodePosZ[0];

		DriverPathLen[driverid] = 0;

		for(new i = 1; arrayid < amount_of_nodes && i < MAX_PATH_LEN; i ++)
		{
		    new Float:dis = floatsqroot(floatpower(NodePosX[arrayid] - DriverPath[driverid][i-1][0], 2) + floatpower(NodePosY[arrayid] - DriverPath[driverid][i-1][1], 2) + floatpower(NodePosZ[arrayid] - DriverPath[driverid][i-1][2], 2));
		    
		    if(arrayid-1 == amount_of_nodes)
		    {
		        DriverPath[driverid][i][0] = NodePosX[amount_of_nodes - 1];
		        DriverPath[driverid][i][1] = NodePosY[amount_of_nodes - 1];
		        DriverPath[driverid][i][2] = NodePosZ[amount_of_nodes - 1];
		        
		        DriverPathLen[driverid] ++;
		        break;
		    }
		    
		    new Float:ndis = MAX_NODE_DIST;

			if(i >= 3 && arrayid < amount_of_nodes - 2)
			{
				new Float:a1 = Get2DAngleOf3Points(DriverPath[driverid][i-2][0], DriverPath[driverid][i-2][1], DriverPath[driverid][i-1][0], DriverPath[driverid][i-1][1], NodePosX[arrayid], NodePosY[arrayid]);
				new Float:a2 = Get2DAngleOf3Points(DriverPath[driverid][i-3][0], DriverPath[driverid][i-3][1], DriverPath[driverid][i-2][0], DriverPath[driverid][i-2][1], DriverPath[driverid][i-1][0], DriverPath[driverid][i-1][1]);
				new Float:a3 = Get2DAngleOf3Points(DriverPath[driverid][i-1][0], DriverPath[driverid][i-1][1], NodePosX[arrayid], NodePosY[arrayid], NodePosX[arrayid+1], NodePosY[arrayid+1]);
				
				if(a1 < 0.0000) a1 *= -1.0;
				if(a2 < 0.0000) a2 *= -1.0;
				if(a3 < 0.0000) a3 *= -1.0;
				
				#define SP_ANGLE 10.0
				
				a1 = (a2 > a1 ? (a3 > a2 ? a3 : a2) : (a3 > a1 ? a3 : a1)); // Confusing but effective, sets a1 to the highest value of a1, a2 or a3
                if(a1 > SP_ANGLE) a1 = SP_ANGLE;

				ndis -= ((a1/SP_ANGLE) * (MAX_NODE_DIST*0.7));

			    new Float: Zrel = (NodePosZ[arrayid] - DriverPath[driverid][i-1][2]) / dis;
			    if(Zrel < 0.0) Zrel *= -3.0;
			    else Zrel *= 3.0;
			    if(Zrel > 0.9) Zrel = 0.9;

			    ndis -= (Zrel * MAX_NODE_DIST * 0.7);
			    
			    #undef SP_ANGLE
		    }
		    else ndis = MAX_NODE_DIST/4.0;
		    
		    if(ndis < MIN_NODE_DIST) ndis = MIN_NODE_DIST;
		    
			if(dis > ndis)
			{
			    new Float:dX, Float:dY, Float:dZ, Float:fact = (dis/ndis);
			    
			    dX = (NodePosX[arrayid] - DriverPath[driverid][i-1][0]) / fact;
			    dY = (NodePosY[arrayid] - DriverPath[driverid][i-1][1]) / fact;
			    dZ = (NodePosZ[arrayid] - DriverPath[driverid][i-1][2]) / fact;
			    
			    DriverPath[driverid][i][0] = DriverPath[driverid][i-1][0] + dX;
			    DriverPath[driverid][i][1] = DriverPath[driverid][i-1][1] + dY;
			    DriverPath[driverid][i][2] = DriverPath[driverid][i-1][2] + dZ;
			    
			    DriverPathLen[driverid] ++;
			    
			    if(dis < (ndis*2.0)) arrayid ++;
			}
			else
			{
			    if(i > 0) i --;
		    	arrayid ++;
			}
		}
		
		if(arrayid < amount_of_nodes - 1) print("[DRIVERS] Error: Could not finish path. Higher MAX_PATH_LEN or MAX_NODE_DIST!");
		
		for(new i = 1; i < DriverPathLen[driverid]; i ++)
		{
			new Float:A = atan2(DriverPath[driverid][i][0] - DriverPath[driverid][i-1][0], DriverPath[driverid][i-1][1] - DriverPath[driverid][i][1]) + 90.0;

			GetXYInFrontOfPoint(DriverPath[driverid][i][0], DriverPath[driverid][i][1], A, newpath[i][0], newpath[i][1], SIDE_DIST);
		}
		
		newpath[0][0] = DriverPath[driverid][0][0];
		newpath[0][1] = DriverPath[driverid][0][1];
		
		newpath = smooth_path(newpath, DriverPathLen[driverid], 0.6, 0.3);
		
		new Float:MapZd, Float:MapZu;
		
		for(new i = 0; i < DriverPathLen[driverid]; i ++)
		{
		    MapZd = RayCastLineZ(newpath[i][0], newpath[i][1], DriverPath[driverid][i][2], -10.0);
			MapZu = RayCastLineZ(newpath[i][0], newpath[i][1], DriverPath[driverid][i][2], 30.0);
			
			if(MapZd == 0.0) MapZd = -990.0;
			if(MapZu == 0.0) MapZu = -990.0;
			
			if(MapZd > -900.0 && MapZu > -900.0)
			{
			    new Float:difd = DriverPath[driverid][i][2] - MapZd, Float:difu = (MapZu - DriverPath[driverid][i][2]);
			    
			    if(difu < difd) DriverPath[driverid][i][2] = MapZu;
				else DriverPath[driverid][i][2] = MapZd;
			}
			else if(MapZd > -900.0) DriverPath[driverid][i][2] = MapZd;
			else if(MapZu > -900.0) DriverPath[driverid][i][2] = MapZu;

		    DriverPath[driverid][i][2] = DriverPath[driverid][i][2] + VehicleZOffsets[Drivers[driverid][nVehicleModel]-400];

			DriverPath[driverid][i][0] = newpath[i][0];
		    DriverPath[driverid][i][1] = newpath[i][1];
		}
		
		Drivers[driverid][nCurNode] = 1;
		Drivers[driverid][nState] = DRIVER_STATE_DRIVE;
		Drivers[driverid][nSpeed] = (MIN_SPEED + MAX_SPEED) / 3.0;
		Drivers[driverid][nDistance] = distance;

		SetTimerEx("FCNPC_OnReachDestination", 50, 0, "d", Drivers[driverid][nNPCID]);

	  	if(Drivers[driverid][nType] == DRIVER_TYPE_TAXI && Drivers[driverid][nOnDuty] && IsPlayerConnected(Drivers[driverid][nPlayer]))
	  	{
	  	    if(TaxiState[Drivers[driverid][nPlayer]] == TAXI_STATE_DRIVE2)
	  	    {
		  	    new roughmins = floatround((distance / (8.3 * MAX_SPEED)) / 60.0);
		  	    
		  	    if(roughmins <= 1) SendClientMessage(Drivers[driverid][nPlayer], -1, "[Taxi Driver]: {009900}I don't like these short ways...");
		  	    else
				{
				    new str[115];
					format(str, sizeof(str), "[Taxi Driver]: {009900}Most say this takes more than %d minutes. But I'll get you there in about %d!", roughmins + 2 + random(4), roughmins);
					SendClientMessage(Drivers[driverid][nPlayer], -1, str);
				}
			}
	  	}
		
		#if DEBUG_PRINTS == true
		if(InitialCalculations <= DRIVER_AMOUNT) printf("[DRIVERS] (%d ms) - PathLen: %d - Nr %d/%d", GetTickCount() - t, DriverPathLen[driverid], InitialCalculations, DRIVER_AMOUNT);
		else printf("[DRIVERS] (%d ms) - PathLen: %d", GetTickCount() - t, DriverPathLen[driverid]);
		#endif
		
		if(InitialCalculations == DRIVER_AMOUNT) { printf("\n[DRIVERS] Initial calculations completed after %.02fs.", (GetTickCount() - InitialCalculationStart) / 1000.0); PrintDriverUpdate(); InitialCalculations = DRIVER_AMOUNT+1; }
		
		if(DriverPathLen[driverid] > MaxPathLen) MaxPathLen = DriverPathLen[driverid];

		if(avgcalcidx >= sizeof(avgcalctimes)) avgcalcidx = 0;
		avgcalctimes[avgcalcidx] = GetTickCount() - t;
		avgcalcidx ++;
		
		return 1;
	}
    
    return 1;
}

public FCNPC_OnReachDestination(npcid)
{
    if(!Initialized) return 1;
    
    new driverid = -1;
	for(new i = 0; i < DRIVER_AMOUNT; i ++)
	{
	    if(npcid != Drivers[i][nNPCID] || !Drivers[i][nUsed]) continue;

		if(Drivers[i][nState] != DRIVER_STATE_DRIVE) break;

	    driverid = i;
	    break;
	}

    if(driverid != -1)
	{
	    #if MAP_ZONES == true
		if(Drivers[driverid][nGangZone] != -1) { GangZoneDestroy(Drivers[driverid][nGangZone]); Drivers[driverid][nGangZone] = -1; }
		#endif
		
		Drivers[driverid][nLT] = GetTickCount();
		
		Drivers[driverid][nCurNode] ++;
		
		if(Drivers[driverid][nIsCop] && random(100) <= 2)
		{
		    if(Drivers[driverid][nLT] - Drivers[driverid][nCopStuffTick] > 9000 && FCNPC_IsVehicleSiren(npcid)) FCNPC_SetVehicleSiren(npcid, false);
		    else if(Drivers[driverid][nLT] - Drivers[driverid][nCopStuffTick] > 90000 && !FCNPC_IsVehicleSiren(npcid))
		    {
		        Drivers[driverid][nCopStuffTick] = Drivers[driverid][nLT];
		        FCNPC_SetVehicleSiren(npcid, true);
		    }
		}
		
		if(Drivers[driverid][nCurNode] == DriverPathLen[driverid]) // Final Destination! >:D
		{
		    if(Drivers[driverid][nType] == DRIVER_TYPE_RANDOM || (Drivers[driverid][nType] == DRIVER_TYPE_TAXI && !Drivers[driverid][nOnDuty]))
		    {
		        Drivers[driverid][nState] = DRIVER_STATE_NONE;
		        
		        new Float:X, Float:Y, Float:Z;
		        FCNPC_GetPosition(npcid, X, Y, Z);
		        
		        new startnode = NearestNodeFromPoint(X, Y, Z);
		        new endnode = -1;
		        
		        do
		        {
					endnode = GetRandomNode();
		        } while(GetDistanceBetweenNodes(startnode, endnode) < ROUTE_MIN_DIST);
		        
		        SetTimerEx("pubCalculatePath", 300, 0, "ddd", driverid, startnode, endnode);
		    }
		    
		    if(Drivers[driverid][nType] == DRIVER_TYPE_TAXI && Drivers[driverid][nOnDuty])
		    {
		        Drivers[driverid][nState] = DRIVER_STATE_NONE;
		        new playerid = Drivers[driverid][nPlayer];
		        
		        if(TaxiState[playerid] == TAXI_STATE_DRIVE1)
		        {
		            SetVehicleParamsForPlayer(Drivers[driverid][nVehicle], playerid, 1, 0);
		            TaxiState[playerid] = TAXI_STATE_WAIT1;
		        }
		        
		        if(TaxiState[playerid] == TAXI_STATE_DRIVE2)
		        {
		            SetVehicleParamsForPlayer(Drivers[driverid][nVehicle], playerid, 0, 1);
					SetTimerEx("pub_RemovePlayerFromVehicle", 1000, 0, "d", playerid);
		            SetTimerEx("ResetTaxi", 10000, 0, "dd", driverid, 0);

			        SendClientMessage(playerid, -1, "[Taxi Driver]: {009900}Hope you enjoyed the ride!");
		        }
		    }
		    
		    #if DEBUG_BUBBLE == true
			new str[40];
			format(str, sizeof(str), "{888888}[%d]\n{880000}Finished!", driverid);
			SetPlayerChatBubble(npcid, str, -1, 10.0, 60000);
			#endif
		    return 1;
		}
		
		new cnode = Drivers[driverid][nCurNode];
		
		if(!IsAnyPlayerInDynamicArea(Drivers[driverid][nStreamingAreaL], 1))
		{
		    if(Drivers[driverid][nCurNode] < DriverPathLen[driverid]-10)
		    {
		        Drivers[driverid][nCurNode] += 3;
		        cnode += 3;
		    }
		    FCNPC_GoTo(npcid, DriverPath[driverid][cnode][0], DriverPath[driverid][cnode][1], DriverPath[driverid][cnode][2], MOVE_TYPE_DRIVE, MAX_SPEED*0.8, false, 0.0, true);
		    Drivers[driverid][nSpeed] = MAX_SPEED*0.7;
		    Drivers[driverid][nActive] = false;

		    return 1;
		}
		
		if(!IsAnyPlayerInDynamicArea(Drivers[driverid][nStreamingAreaS], 1))
		{
		    new Float:X, Float:Y, Float:Z, Float:Qw, Float:Qx, Float:Qy, Float:Qz;
			FCNPC_GetPosition(npcid, X, Y, Z);
			GetQuatRotForVehBetweenCoords2D(X, Y, Z, DriverPath[driverid][cnode][0], DriverPath[driverid][cnode][1], DriverPath[driverid][cnode][2], Qw, Qx, Qy, Qz);
			
	        FCNPC_GoTo(npcid, DriverPath[driverid][cnode][0], DriverPath[driverid][cnode][1], DriverPath[driverid][cnode][2], MOVE_TYPE_DRIVE, MAX_SPEED*0.7, false, 0.0, false);
	        FCNPC_SetQuaternion(npcid, Qw, Qx, Qy, Qz);
	        
	        Drivers[driverid][nSpeed] = MAX_SPEED*0.7;
	        Drivers[driverid][nActive] = false;

	        return 1;
		}
		
		Drivers[driverid][nActive] = true;
		
	    new Float:X, Float:Y, Float:Z;
		FCNPC_GetPosition(npcid, X, Y, Z);
		
		if(X < -3000.0) X = -3000.0;
		if(X > 3000.0) X = 3000.0;
		if(Y < -3000.0) Y = -3000.0;
		if(Y > 3000.0) Y = 3000.0;
		
		Drivers[driverid][nZoneX] = floatround((X + 3000.0) / 6000.0 * ZONES_NUM);
		Drivers[driverid][nZoneY] = floatround((Y + 3000.0) / 6000.0 * ZONES_NUM);
		
		new Float:A1 = FCNPC_GetAngle(Drivers[driverid][nNPCID]), Float:A2, bool:blocked = false, Float:x2, Float:y2, Float:z2;
		
		GetVehicleZAngle(Drivers[driverid][nVehicle], A1);
		
		for(new i = 0; i < DRIVER_AMOUNT; i ++)
		{
		    if(!Drivers[i][nUsed] || !Drivers[i][nActive] || i == driverid) continue;

			if(!FCNPC_IsValid(Drivers[i][nNPCID])) continue;

		    if(Drivers[driverid][nZoneX] != Drivers[i][nZoneX] || Drivers[driverid][nZoneY] != Drivers[i][nZoneY]) continue;
		    
		    FCNPC_GetPosition(Drivers[i][nNPCID], x2, y2, z2);

		    if(floatsqroot(floatpower(x2-X, 2) + floatpower(y2-Y, 2)) >= JAM_DIST) continue; // Distance between both NPCs

		    GetVehicleZAngle(Drivers[i][nVehicle], A2);
		    
		    if(floatangledist(A1, A2) >= JAM_ANGLE) continue; // Angle distance between both NPCs (do they face the same direction?)
		    
		    if(floatangledist(A1, 360.0-atan2(x2-X, y2-Y)) >= JAM_ANGLE) continue; // Angle distance between NPC1 and the direction to NPC2 (is NPC1 going in NPC2's direction?) - Criteria for being behind!

		    blocked = true;
		    if(Drivers[driverid][nSpeed] >= Drivers[i][nSpeed]-0.1) Drivers[driverid][nSpeed] = Drivers[i][nSpeed] - 0.1;
		    else Drivers[driverid][nSpeed] -= (0.05 + (random(1000)/10000.0));
		    
		    break;
		}

		if(!blocked)
		{
			new Float:AimedSpeed;
			if(cnode > 1 && cnode < DriverPathLen[driverid]-3)
			{
				new Float:Xdif = DriverPath[driverid][cnode][0] - X, Float:Ydif = DriverPath[driverid][cnode][1] - Y, Float:Zdif = DriverPath[driverid][cnode][2] - Z;

				new Float:dif = floatsqroot(Xdif*Xdif + Ydif*Ydif);
				if(dif == 0.0) dif = 1.0;
				else dif = Zdif / dif;

				if(dif < 0.0) dif *= -1.0;
				if(dif > 1.0) dif = 1.0;

			  	AimedSpeed = MAX_SPEED - (1.7*dif*(MAX_SPEED-MIN_SPEED)); // base speed based on steepness
			  	
			  	new Float:Adif = Get2DAngleOf3Points(DriverPath[driverid][cnode-1][0], DriverPath[driverid][cnode-1][1], DriverPath[driverid][cnode][0], DriverPath[driverid][cnode][1], DriverPath[driverid][cnode+1][0], DriverPath[driverid][cnode+1][1]);

		  	    if(Adif < 0.0) Adif *= -1.0;
		  	    if(Adif > 50.0) Adif = 50.0;

				AimedSpeed = AimedSpeed - ((AimedSpeed/80.0) * Adif);

		  	}
		  	else if(Drivers[driverid][nOnDuty] && Drivers[driverid][nType] == DRIVER_TYPE_TAXI) AimedSpeed = Drivers[driverid][nSpeed] * 0.7;
		  	else AimedSpeed = (MIN_SPEED + MAX_SPEED) / 2.0;

		  	if(AimedSpeed < Drivers[driverid][nSpeed]) Drivers[driverid][nSpeed] = (Drivers[driverid][nSpeed] + AimedSpeed*4.0) / 5.0;
		  	else Drivers[driverid][nSpeed] += (AimedSpeed - Drivers[driverid][nSpeed]) / (Drivers[driverid][nSpeed]*7.0) + 0.02;
		}
		
	  	if(Drivers[driverid][nSpeed] > MAX_SPEED) Drivers[driverid][nSpeed] = MAX_SPEED;
	  	if(Drivers[driverid][nSpeed] < MIN_SPEED) Drivers[driverid][nSpeed] = MIN_SPEED;
	  	
	  	if(!blocked && FCNPC_IsVehicleSiren(npcid)) Drivers[driverid][nSpeed] += 0.45;
	  	
        new Float:Qw, Float:Qx, Float:Qy, Float:Qz;
		FCNPC_GetPosition(npcid, X, Y, Z);
		GetQuatRotForVehBetweenCoords2D(X, Y, Z, DriverPath[driverid][cnode][0], DriverPath[driverid][cnode][1], DriverPath[driverid][cnode][2], Qw, Qx, Qy, Qz);

		FCNPC_GoTo(npcid, DriverPath[driverid][cnode][0], DriverPath[driverid][cnode][1], DriverPath[driverid][cnode][2], MOVE_TYPE_DRIVE, Drivers[driverid][nSpeed], false, 0.0, false);
        FCNPC_SetQuaternion(npcid, Qw, Qx, Qy, Qz);

		#if MAP_ZONES == true
		Drivers[driverid][nGangZone] = GangZoneCreate(X-4.5, Y-4.5, X+4.5, Y+4.5);
		GangZoneShowForAll(Drivers[driverid][nGangZone], 0x66FF00FF);
		#endif

	    #if DEBUG_BUBBLE == true
		new str[65];
		format(str, sizeof(str), "{888888}[%d]\nX:%d Y:%d B:%b\n {666666}Speed: %.02f ", driverid, Drivers[driverid][nZoneX], Drivers[driverid][nZoneY], blocked, Drivers[driverid][nSpeed]);
		SetPlayerChatBubble(npcid, str, -1, 10.0, 5000);
		#endif

		return 1;
	}
	return 1;
}

// -----------------------------------------------------------------------------

forward Float:smooth_path(Float:path[][S_DIMENSIONS], len = sizeof path, Float:weight_data = 0.5, Float:weight_smooth = 0.1);
Float:smooth_path(Float:path[][S_DIMENSIONS], len = sizeof path, Float:weight_data = 0.5, Float:weight_smooth = 0.1) // Basic Smoothing algorithm I (NaS) converted from Python - All nodes orientate at 2 coords in a relation (defined by weight_data & weight_smooth), the original data and the smooth path - Can smooth 1D, 2D or 3D (Even more :O)
{
	new Float:change = 1.0, Float:npath[MAX_SMOOTH_PATH][S_DIMENSIONS];

	for(new i = 0; i < len; i ++) for(new j = 0; j < S_DIMENSIONS; j ++) npath[i][j] = path[i][j];

	while(change >= 0.0003)
	{
	    change = 0.0;

		for(new i = 1; i < len - 1; i ++) // all nodes except start & end
		{
			for(new j = 0; j < S_DIMENSIONS; j ++)
			{
			    new Float:aux = npath[i][j];

			    npath[i][j] = npath[i][j] + weight_data * (path[i][j] - npath[i][j]); // Drag node to original pos (with factor)
			    npath[i][j] = npath[i][j] + weight_smooth * (npath[i-1][j] + npath[i+1][j] - (2.0 * npath[i][j])); // Drag node to interpolated pos (with factor)

			    change += floatabs(aux - npath[i][j]);
			}
		}
	}
	return npath;
}

stock GetXYInFrontOfPoint(Float:gX, Float:gY, Float:R, &Float:x, &Float:y, Float:distance)
{	// Created by Y_Less
	x=gX;
	y=gY;

	x += (distance * floatsin(-R, degrees));
	y += (distance * floatcos(-R, degrees));
}

stock strtok(const string[], &index) // Please don't complain about this - it will be gone soon!
{
	new length = strlen(string);
	while ((index < length) && (string[index] <= ' '))
	{
		index++;
	}

	new offset = index;
	new result[128];
	while ((index < length) && (string[index] > ' ') && ((index - offset) < (sizeof(result) - 1)))
	{
		result[index - offset] = string[index];
		index++;
	}
	result[index - offset] = EOS;
	return result;
}

stock HidePlayerDialog(playerid) return ShowPlayerDialog(playerid,-1,0," "," "," "," ");

stock GetRandomNode()
{
	if(RandomNodesNum < 1 || RandomNodesNum >= MAX_RANDOM_NODES) return -1;
	
	return RandomNodes[random(RandomNodesNum)];
}

forward Float:Get2DAngleOf3Points(Float:x1, Float:y1, Float:x2, Float:y2, Float:x3, Float:y3);
Float:Get2DAngleOf3Points(Float:x1, Float:y1, Float:x2, Float:y2, Float:x3, Float:y3)
{
	return floatabs(atan2(x1-x2, y1-y2)) - floatabs(atan2(x2-x3, y2-y3));
}

forward Float:RayCastLineZ(Float:X, Float:Y, Float:Z, Float:dist);
Float:RayCastLineZ(Float:X, Float:Y, Float:Z, Float:dist)
{
	if(CA_RayCastLine(X, Y, Z, X, Y, Z + dist, X, Y, Z)) return Z;
	else return -999.0;
}

stock floatangledist(Float:alpha, Float:beta) // Ranging from 0 to 180, not directional (left/right)
{
    new phi = floatround(floatabs(beta - alpha), floatround_floor) % 360;
    new distance = phi > 180 ? 360 - phi : phi;
    return distance;
}

// --- EOF ---
